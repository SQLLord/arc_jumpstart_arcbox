"""Generate ARM/createUiDefinition.json for the ArcBox portal deployment form.

The form uses the portal VM size picker (Microsoft.Compute.SizeSelector) and checks that the
per-VM data disks do not add up to more IOPS / throughput than the selected VM size supports.
Both need the list of allowed VM sizes and their disk limits, which this script reads from
Azure (az vm list-skus) and bakes into the form. It also updates the clientVmSize allowed
values in ARM/azuredeploy.json and bicep/main.bicep so the template accepts the same sizes.

Re-run it when Azure adds new VM sizes or when the template parameters change:

    az login
    python azure_jumpstart_arcbox/ARM/tools/generate_createuidefinition.py [--region westus2] [--skus-file skus.json]

--skus-file takes the JSON output of `az vm list-skus -l <region> --resource-type virtualMachines -o json`
instead of calling the Azure CLI. Disk limits of a VM size are the same in every region.
"""
import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import sys

OD = collections.OrderedDict

ARCBOX_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
UI_DEFINITION = os.path.join(ARCBOX_DIR, 'ARM', 'createUiDefinition.json')
ARM_TEMPLATE = os.path.join(ARCBOX_DIR, 'ARM', 'azuredeploy.json')
MAIN_BICEP = os.path.join(ARCBOX_DIR, 'bicep', 'main.bicep')

# Allowed client VM sizes: D/E-series v5 or newer, x64 (no 'p' Arm64 sizes), 8-64 vCPUs, 32+ GB memory
SIZE_PATTERN = re.compile(r'^Standard_([DE])(\d+)([a-z]*)_v(\d+)$')
MIN_VERSION, MIN_VCPUS, MAX_VCPUS, MIN_MEMORY_GB = 5, 8, 64, 32

# Disks on the client VM besides the per-VM disks with the PerVM layout (see bicep/clientVm/clientVm.bicep):
# OS disk P10 (500 IOPS / 100 MB/s) and the shared VMs disk at the Premium SSD v2 baseline (3000 IOPS / 125 MB/s)
BASE_IOPS, BASE_MBPS = 500 + 3000, 100 + 125
PERVM_DEFAULT_IOPS, PERVM_DEFAULT_MBPS = 3000, 125
ITPRO_NESTED_VMS = 5

# Per-VM disks must stay smaller than the shared VMs disk, which Bootstrap.ps1 identifies as the largest data disk
SHARED_DISK_GB = 256
PERVM_DISK_STEP_GB = 32
PERVM_DISK_MAX_GB = (SHARED_DISK_GB - 1) // PERVM_DISK_STEP_GB * PERVM_DISK_STEP_GB  # 224


def load_skus(args):
    if args.skus_file:
        with open(args.skus_file, encoding='utf-8') as f:
            return json.load(f)
    az = shutil.which('az') or shutil.which('az.cmd')
    if not az:
        sys.exit('Azure CLI (az) not found. Install it or pass --skus-file.')
    print(f'Reading VM sizes for {args.region} from Azure...')
    out = subprocess.run([az, 'vm', 'list-skus', '-l', args.region, '--resource-type', 'virtualMachines', '-o', 'json'],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def allowed_sizes(skus):
    """Returns {size: [uncached disk IOPS, uncached disk MB/s]} sorted by version, family, suffix, vCPUs."""
    found = {}
    for sku in skus:
        match = SIZE_PATTERN.match(sku.get('name', ''))
        if not match:
            continue
        family, vcpus, suffix, version = match.group(1), int(match.group(2)), match.group(3), int(match.group(4))
        caps = {c['name']: c['value'] for c in sku.get('capabilities', [])}
        if (version < MIN_VERSION or not MIN_VCPUS <= vcpus <= MAX_VCPUS or 'p' in suffix
                or float(caps.get('MemoryGB', 0)) < MIN_MEMORY_GB
                or 'UncachedDiskIOPS' not in caps or 'UncachedDiskBytesPerSecond' not in caps):
            continue
        found[(version, family, suffix, vcpus, sku['name'])] = [
            int(caps['UncachedDiskIOPS']), int(caps['UncachedDiskBytesPerSecond']) // 1048576]
    return OD((key[4], value) for key, value in sorted(found.items()))


def el(**k):
    return OD(k)


def build_ui_definition(caps):
    sizes = list(caps)
    pervm_sizes = [n for n in sizes
                   if caps[n][0] >= BASE_IOPS + ITPRO_NESTED_VMS * PERVM_DEFAULT_IOPS
                   and caps[n][1] >= BASE_MBPS + ITPRO_NESTED_VMS * PERVM_DEFAULT_MBPS]

    VM, NET, ADV = "steps('vm')", "steps('network')", "steps('advanced')"
    IS_PERVM = f"equals({VM}.nestedVmDiskLayout, 'PerVM')"
    PERVM_SIZE = f'{VM}.clientVmSizePerVm'
    NESTED_VM_COUNT = "if(equals(basics('flavor'), 'ITPro'), 5, if(equals(basics('flavor'), 'DataOps'), 1, 0))"

    def headroom(index, base):
        """Expression for the IOPS (index 0) or MB/s (index 1) the selected PerVM size has left for the per-VM disks
        after the OS and shared disks. Sizes are grouped by limit and matched with contains() on a |size|size| list,
        since the portal does not evaluate string-parsing lookups reliably. Unknown sizes get 0 and fail the check."""
        groups = collections.defaultdict(list)
        for n in pervm_sizes:
            groups[caps[n][index]].append(n)
        expr = '0'
        for limit in sorted(groups):
            members = '|' + '|'.join(groups[limit]) + '|'
            expr = f"if(contains('{members}', concat('|', {PERVM_SIZE}, '|')), {limit - base}, {expr})"
        return expr

    # Per-VM disks fit when count x per-disk value <= VM limit - (OS disk + shared disk)
    FITS_IOPS = f'lessOrEquals(mul({NESTED_VM_COUNT}, {VM}.nestedVmDiskIOPS), {headroom(0, BASE_IOPS)})'
    FITS_MBPS = f'lessOrEquals(mul({NESTED_VM_COUNT}, {VM}.nestedVmDiskMBps), {headroom(1, BASE_MBPS)})'
    SIZE_SELECTOR = dict(
        type='Microsoft.Compute.SizeSelector', label='Client VM size', osPlatform='Windows',
        imageReference=OD(publisher='MicrosoftWindowsServer', offer='WindowsServer', sku='2025-datacenter-g2'), count=1)

    basics = [
        el(name='flavor', type='Microsoft.Common.DropDown', label='ArcBox flavor', defaultValue='ITPro',
           toolTip='Which ArcBox scenario to deploy.',
           constraints=OD(allowedValues=[OD(label=x, value=x) for x in ('ITPro', 'DevOps', 'DataOps')], required=True)),
        el(name='sqlServerEdition', type='Microsoft.Common.DropDown', label='SQL Server edition', defaultValue='Developer',
           toolTip='Edition of SQL Server on the nested SQL VM.',
           constraints=OD(allowedValues=[OD(label=x, value=x) for x in ('Developer', 'Standard', 'Enterprise')], required=True)),
        el(name='namingPrefix', type='Microsoft.Common.TextBox', label='Naming prefix', defaultValue='ArcBox',
           toolTip='Prefix for all resources and nested VMs (max 7 characters).',
           constraints=OD(required=True, regex='^[A-Za-z][A-Za-z0-9]{0,6}$',
                          validationMessage='1-7 letters or numbers, starting with a letter.')),
        el(name='logAnalyticsWorkspaceName', type='Microsoft.Common.TextBox', label='Log Analytics workspace name',
           defaultValue='ArcBox-la',
           constraints=OD(required=True, regex='^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$',
                          validationMessage='4-63 letters, numbers or hyphens.')),
        el(name='windowsAdminUsername', type='Microsoft.Compute.UserNameTextBox', label='Windows admin username',
           defaultValue='arcdemo', osPlatform='Windows', toolTip='Admin account for the client VM.',
           constraints=OD(required=True)),
        el(name='windowsAdminPassword', type='Microsoft.Common.PasswordBox',
           label=OD(password='Windows admin password', confirmPassword='Confirm password'),
           toolTip='12-123 characters with upper case, lower case, a number and a special character.',
           constraints=OD(required=True, regex='^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[^A-Za-z0-9]).{12,123}$',
                          validationMessage='12-123 characters with upper case, lower case, a number and a special character.'),
           options=OD(hideConfirmation=False)),
        el(name='sshRSAPublicKey', type='Microsoft.Common.TextBox', label='SSH RSA public key', multiLine=True,
           toolTip='Required for the DevOps and DataOps flavors (K3s/AKS Linux nodes).',
           visible="[not(equals(basics('flavor'), 'ITPro'))]",
           constraints=OD(required="[not(equals(basics('flavor'), 'ITPro'))]")),
    ]

    vm = [
        el(name='nestedVmDiskLayout', type='Microsoft.Common.OptionsGroup', label='Nested VM disks', defaultValue='One shared disk',
           toolTip='One shared disk: all nested VM VHDX files on one data disk. One disk per nested VM: an extra Premium SSD v2 data disk for each nested VM, so they do not compete for IOPS. Total disk performance is still capped by the client VM size.',
           constraints=OD(allowedValues=[OD(label='One shared disk', value='Shared'),
                                         OD(label='One disk per nested VM', value='PerVM')], required=True)),
        el(name='clientVmSizeShared', **SIZE_SELECTOR,
           toolTip='Size of the ArcBox client VM that hosts the nested VMs. Limited to v5 or newer D/E-series x64 sizes with 8+ vCPUs and 32+ GB of memory.',
           recommendedSizes=[s for s in ['Standard_D8s_v7', 'Standard_D16s_v7', 'Standard_E8s_v7', 'Standard_D8ds_v6', 'Standard_D8s_v6'] if s in sizes],
           constraints=OD(allowedSizes=sizes), visible=f'[not({IS_PERVM})]'),
        el(name='clientVmSizePerVm', **SIZE_SELECTOR,
           toolTip='Size of the ArcBox client VM. With one disk per nested VM, only sizes whose disk IOPS and throughput limits can drive the default per-VM disks are shown.',
           recommendedSizes=[s for s in ['Standard_D16s_v7', 'Standard_D32s_v7', 'Standard_E16s_v7', 'Standard_D16ds_v7'] if s in pervm_sizes],
           constraints=OD(allowedSizes=pervm_sizes), visible=f'[{IS_PERVM}]'),
        el(name='nestedVmDiskSizeGB', type='Microsoft.Common.Slider', label='Per-VM disk size', subLabel='GB',
           min=64, max=PERVM_DISK_MAX_GB, step=PERVM_DISK_STEP_GB, defaultValue=128, showStepMarkers=False,
           visible=f'[{IS_PERVM}]',
           toolTip=f'Size of each per-VM data disk (largest VHDX, SQL, is about 58 GB). Capped below the {SHARED_DISK_GB} GB shared VMs disk.',
           constraints=OD(required=True)),
        el(name='nestedVmDiskIOPS', type='Microsoft.Common.Slider', label='Per-VM disk IOPS', subLabel='IOPS',
           min=3000, max=80000, step=1000, defaultValue=PERVM_DEFAULT_IOPS, showStepMarkers=False,
           visible=f'[{IS_PERVM}]',
           toolTip='Premium SSD v2 includes 3000 IOPS per disk at no extra charge. Max 500 IOPS per GB of disk size.',
           constraints=OD(required=True)),
        el(name='nestedVmDiskMBps', type='Microsoft.Common.Slider', label='Per-VM disk throughput', subLabel='MB/s',
           min=125, max=1200, step=25, defaultValue=PERVM_DEFAULT_MBPS, showStepMarkers=False,
           visible=f'[{IS_PERVM}]',
           toolTip='Premium SSD v2 includes 125 MB/s per disk at no extra charge. Max 0.25 MB/s per IOPS.',
           constraints=OD(required=True)),
        el(name='diskPerformanceCheck', type='Microsoft.Common.TextBox', label='Disk performance check', readOnly=True,
           defaultValue='Checked against the selected VM size',
           toolTip='Adds up the provisioned IOPS and throughput of every disk on the client VM: OS disk (500 IOPS / 100 MB/s), shared VMs disk (3000 IOPS / 125 MB/s) and one per-VM disk per nested VM (5 for ITPro, 1 for DataOps), and compares them with the VM size limits.',
           visible=f'[{IS_PERVM}]',
           constraints=OD(required=False, validations=[
               OD(isValid=f'[less({VM}.nestedVmDiskSizeGB, {SHARED_DISK_GB})]',
                  message=f'Per-VM disks must be smaller than the {SHARED_DISK_GB} GB shared VMs disk.'),
               OD(isValid=f'[lessOrEquals({VM}.nestedVmDiskIOPS, mul(500, {VM}.nestedVmDiskSizeGB))]',
                  message='Per-VM disk IOPS is above the Premium SSD v2 limit of 500 IOPS per GB. Lower the IOPS or increase the disk size.'),
               OD(isValid=f'[lessOrEquals(mul(4, {VM}.nestedVmDiskMBps), {VM}.nestedVmDiskIOPS)]',
                  message='Per-VM disk throughput is above the Premium SSD v2 limit of 0.25 MB/s per IOPS. Lower the throughput or raise the IOPS.'),
               OD(isValid=f'[or(empty({PERVM_SIZE}), {FITS_IOPS})]',
                  message='The disks add up to more IOPS than the selected VM size supports. Lower the per-VM disk IOPS or choose a larger VM size.'),
               OD(isValid=f'[or(empty({PERVM_SIZE}), {FITS_MBPS})]',
                  message='The disks add up to more throughput (MB/s) than the selected VM size supports. Lower the per-VM disk throughput or choose a larger VM size.'),
           ])),
        el(name='zones', type='Microsoft.Common.DropDown', label='Availability zone', defaultValue='1',
           constraints=OD(allowedValues=[OD(label=z, value=z) for z in ('1', '2', '3')], required=True)),
        el(name='enableAzureSpotPricing', type='Microsoft.Common.CheckBox', label='Use Azure Spot pricing for the client VM'),
        el(name='vmAutologon', type='Microsoft.Common.CheckBox', defaultValue=True,
           label='Enable autologon (runs the setup scripts automatically after reboot)'),
        el(name='autoShutdownEnabled', type='Microsoft.Common.CheckBox', label='Enable daily auto-shutdown', defaultValue=True),
        el(name='autoShutdownTime', type='Microsoft.Common.TextBox', label='Auto-shutdown time (HHmm)', defaultValue='1800',
           visible=f'[{VM}.autoShutdownEnabled]',
           constraints=OD(required=True, regex='^([01][0-9]|2[0-3])[0-5][0-9]$',
                          validationMessage='24-hour time as HHmm, for example 1800.')),
        el(name='autoShutdownTimezone', type='Microsoft.Common.TextBox', label='Auto-shutdown time zone', defaultValue='UTC',
           visible=f'[{VM}.autoShutdownEnabled]',
           toolTip='Windows time zone ID, for example "UTC" or "Pacific Standard Time".',
           constraints=OD(required=True)),
        el(name='autoShutdownEmailRecipient', type='Microsoft.Common.TextBox',
           label='Auto-shutdown notification email (optional)', visible=f'[{VM}.autoShutdownEnabled]',
           constraints=OD(required=False)),
    ]

    net = [
        el(name='deployNatGateway', type='Microsoft.Common.CheckBox', label='Deploy a NAT Gateway for outbound internet access',
           toolTip='Required where policy blocks default outbound access. Always deployed with Bastion or the DevOps/DataOps flavors.'),
        el(name='deployBastion', type='Microsoft.Common.CheckBox', label='Deploy Azure Bastion (client VM gets no public IP)'),
        el(name='bastionSku', type='Microsoft.Common.DropDown', label='Bastion SKU', defaultValue='Basic',
           visible=f'[{NET}.deployBastion]',
           constraints=OD(allowedValues=[OD(label=x, value=x) for x in ('Basic', 'Standard', 'Developer')], required=True)),
        el(name='rdpPort', type='Microsoft.Common.TextBox', label='RDP port', defaultValue='3389',
           constraints=OD(required=True, regex='^[0-9]{2,5}$', validationMessage='A port number.')),
    ]

    adv = [
        el(name='githubAccount', type='Microsoft.Common.TextBox', label='GitHub account hosting arc_jumpstart_arcbox',
           defaultValue='SQLLord', constraints=OD(required=True)),
        el(name='githubBranch', type='Microsoft.Common.TextBox', label='GitHub branch', defaultValue='master',
           constraints=OD(required=True)),
        el(name='githubUser', type='Microsoft.Common.TextBox', label='GitHub account hosting jumpstart-apps (DevOps only)',
           defaultValue='Azure', constraints=OD(required=True)),
        el(name='vhdStorageAccountName', type='Microsoft.Common.TextBox',
           label='VHD storage account (empty = public Jumpstart storage)', defaultValue='arcboxfilesdonotdelete',
           constraints=OD(required=False)),
        el(name='vhdStorageAccountResourceGroup', type='Microsoft.Common.TextBox', label='VHD storage account resource group',
           defaultValue='Arcbox', visible=f'[not(empty({ADV}.vhdStorageAccountName))]', constraints=OD(required=True)),
        el(name='vhdContainerName', type='Microsoft.Common.TextBox', label='VHD container', defaultValue='arcboxvhds',
           visible=f'[not(empty({ADV}.vhdStorageAccountName))]', constraints=OD(required=True)),
        el(name='keyVaultName', type='Microsoft.Common.TextBox', label='Key Vault name (empty = auto-generated)',
           constraints=OD(required=False, regex='^$|^[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]$',
                          validationMessage='3-24 letters, numbers or hyphens, starting with a letter.')),
        el(name='debugEnabled', type='Microsoft.Common.CheckBox', label='Debug mode for the automation scripts'),
    ]

    outputs = OD(location='[location()]')
    for e in basics:
        outputs[e['name']] = f"[basics('{e['name']}')]"
    for step, elements in ((VM, vm), (NET, net), (ADV, adv)):
        for e in elements:
            outputs[e['name']] = f"[{step}.{e['name']}]"

    # Hidden fields send the template default instead of relying on the portal's value for hidden elements
    hidden_defaults = {
        'sshRSAPublicKey': ("not(equals(basics('flavor'), 'ITPro'))", "basics('sshRSAPublicKey')", "''"),
        'nestedVmDiskSizeGB': (IS_PERVM, f'{VM}.nestedVmDiskSizeGB', '128'),
        'nestedVmDiskIOPS': (IS_PERVM, f'{VM}.nestedVmDiskIOPS', str(PERVM_DEFAULT_IOPS)),
        'nestedVmDiskMBps': (IS_PERVM, f'{VM}.nestedVmDiskMBps', str(PERVM_DEFAULT_MBPS)),
        'autoShutdownTime': (f'{VM}.autoShutdownEnabled', f'{VM}.autoShutdownTime', "'1800'"),
        'autoShutdownTimezone': (f'{VM}.autoShutdownEnabled', f'{VM}.autoShutdownTimezone', "'UTC'"),
        'autoShutdownEmailRecipient': (f'{VM}.autoShutdownEnabled', f'{VM}.autoShutdownEmailRecipient', "''"),
        'bastionSku': (f'{NET}.deployBastion', f'{NET}.bastionSku', "'Basic'"),
        'vhdStorageAccountResourceGroup': (f'not(empty({ADV}.vhdStorageAccountName))', f'{ADV}.vhdStorageAccountResourceGroup', "'Arcbox'"),
        'vhdContainerName': (f'not(empty({ADV}.vhdStorageAccountName))', f'{ADV}.vhdContainerName', "'arcboxvhds'"),
    }
    for name, (condition, value, default) in hidden_defaults.items():
        outputs[name] = f'[if({condition}, {value}, {default})]'

    # One template parameter fed by whichever size selector is visible; the check box is UI only
    for name in ('clientVmSizeShared', 'clientVmSizePerVm', 'diskPerformanceCheck'):
        del outputs[name]
    outputs['clientVmSize'] = f'[if({IS_PERVM}, {VM}.clientVmSizePerVm, {VM}.clientVmSizeShared)]'

    ui = OD()
    ui['$schema'] = 'https://schema.management.azure.com/schemas/0.1.2-preview/CreateUIDefinition.MultiVm.json#'
    ui['handler'] = 'Microsoft.Azure.CreateUIDef'
    ui['version'] = '0.1.2-preview'
    ui['parameters'] = OD(
        config=OD(isWizard=False, basics=OD(description='Deploys Arc Jumpstart ArcBox. Pick the flavor here; the client VM size, networking and source settings are on the following tabs.')),
        basics=basics,
        steps=[OD(name='vm', label='Client VM', elements=vm),
               OD(name='network', label='Networking', elements=net),
               OD(name='advanced', label='Advanced', elements=adv)],
        outputs=outputs,
    )
    return ui, sizes, pervm_sizes


def update_template_allowed_sizes(sizes):
    """Keeps the clientVmSize allowed values of the ARM template and main.bicep in line with the form."""
    with open(ARM_TEMPLATE, encoding='utf-8') as f:
        template = json.load(f, object_pairs_hook=OD)
    template['parameters']['clientVmSize']['allowedValues'] = [''] + sizes
    with open(ARM_TEMPLATE, 'w', encoding='utf-8') as f:
        f.write(json.dumps(template, indent=2, ensure_ascii=False))

    with open(MAIN_BICEP, encoding='utf-8') as f:
        bicep = f.read()
    allowed = "@allowed([\n  ''\n" + ''.join(f"  '{s}'\n" for s in sizes) + '])\n'
    bicep, count = re.subn(r"@allowed\(\[\n  ''\n(?:  'Standard_[^']+'\n)+\]\)\n(?=param clientVmSize )", lambda _: allowed, bicep)
    if count != 1:
        sys.exit('Could not find the clientVmSize @allowed block in bicep/main.bicep')
    with open(MAIN_BICEP, 'w', encoding='utf-8') as f:
        f.write(bicep)
    return template


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--region', default='westus2', help='Region to read VM sizes from (default: westus2)')
    parser.add_argument('--skus-file', help='JSON output of az vm list-skus to use instead of calling Azure')
    args = parser.parse_args()

    caps = allowed_sizes(load_skus(args))
    if not caps:
        sys.exit('No matching VM sizes found.')
    ui, sizes, pervm_sizes = build_ui_definition(caps)

    with open(UI_DEFINITION, 'w', encoding='utf-8') as f:
        f.write(json.dumps(ui, indent=2, ensure_ascii=False) + '\n')
    template = update_template_allowed_sizes(sizes)

    # Every form output must be a template parameter, and every required template parameter must be supplied
    outputs = set(ui['parameters']['outputs'])
    unknown = outputs - set(template['parameters'])
    missing = [k for k, v in template['parameters'].items() if 'defaultValue' not in v and k not in outputs]
    if unknown or missing:
        sys.exit(f'Form and template are out of sync. Unknown outputs: {sorted(unknown)}; required parameters not supplied: {missing}')

    print(f'Wrote {os.path.relpath(UI_DEFINITION, ARCBOX_DIR)}: {len(sizes)} sizes, {len(pervm_sizes)} for the PerVM disk layout')
    print('Updated clientVmSize allowed values in ARM/azuredeploy.json and bicep/main.bicep')


if __name__ == '__main__':
    main()

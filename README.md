[![Stale Branches](https://github.com/SQLLord/arc_jumpstart_arcbox/actions/workflows/stale-branches.yml/badge.svg)](https://github.com/SQLLord/arc_jumpstart_arcbox/actions/workflows/stale-branches.yml)

# ⚡ Arc Jumpstart source code

Welcome to the Arc Jumpstart source code repository! This repository is your go-to resource for working with and contributing to the Arc Jumpstart automation scripts and tools and acts as the backend source code repository which complements our [documentation repository](https://github.com/SQLLord/arc_jumpstart_Arcbox_docs) that eventually populates the [Arc Jumpstart](https://aka.ms/arcjumpstart) website.

<p align="center">
  <img src="https://github.com/SQLLord/arc_jumpstart_Arcbox_docs/raw/master/img/logo/jumpstart.png" alt="Arc Jumpstart logo" width="320">
</p>

**Note:** This repository does not contain the source code for the documentation of the Arc Jumpstart which can be found in another [dedicated repository](https://github.com/SQLLord/arc_jumpstart_Arcbox_docs).

## 📦 What you'll find here

- **Automation Source Code:** Arc Jumpstart automation scripts and tools utilized in our scenarios and solutions.
- **Supportive Documents and Files:** Additional resources used across the [Arc Jumpstart](https://aka.ms/ArcJumpstart) website, aiding in various contexts and providing supplemental information.

## 🚀 Deploy ArcBox

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FSQLLord%2Farc_jumpstart_arcbox%2Fmaster%2Fazure_jumpstart_arcbox%2FARM%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FSQLLord%2Farc_jumpstart_arcbox%2Fmaster%2Fazure_jumpstart_arcbox%2FARM%2FcreateUiDefinition.json)

The button opens the ArcBox deployment form in the Azure portal. Compared with a plain custom deployment, the form adds:

- **Client VM size picker** with pricing and availability for your subscription (v5 or newer D/E-series x64 sizes with 8+ vCPUs and 32+ GB of memory).
- **Nested VM disks**: one shared data disk, or one Premium SSD v2 data disk per nested VM. With one disk per nested VM, only larger VM sizes are offered, and the form blocks the deployment if the disks add up to more IOPS or throughput than the VM size supports.
- **Networking options**: NAT Gateway for outbound internet access (for environments where policy blocks default outbound access), a private endpoint for the Key Vault (for environments where policy disables public network access on Key Vaults) and Azure Bastion.

### Connecting to the client VM

- **Without Bastion:** RDP to the client VM's public IP. Add an NSG rule for your own IP address first; ArcBox does not open RDP to the internet.
- **With Bastion (any SKU):** in the portal, open the `ArcBox-Client` VM and choose **Connect > Bastion** to connect in the browser.
- **With Bastion Standard or Premium:** connect with the Windows Remote Desktop app (native client support is enabled for these SKUs). The desktop wallpaper with the deployment test results shows in this client:

  ```powershell
  az network bastion rdp --name ArcBox-Bastion --resource-group <resource-group> `
    --target-resource-id $(az vm show --resource-group <resource-group> --name ArcBox-Client --query id --output tsv)
  ```

  This needs the Azure CLI `bastion` extension, which is installed on first use. Use your naming prefix instead of `ArcBox` if you changed it.

The form is defined in [`createUiDefinition.json`](azure_jumpstart_arcbox/ARM/createUiDefinition.json), and the template it deploys is [`azuredeploy.json`](azure_jumpstart_arcbox/ARM/azuredeploy.json). When Azure adds new VM sizes, regenerate the form and the template's allowed sizes:

```bash
az login
python azure_jumpstart_arcbox/ARM/tools/generate_createuidefinition.py
```

## 🛠️ How to Utilize this repository

This source code repository is designed with contributors in mind and works in tandem with the [our documentation repository](https://github.com/SQLLord/arc_jumpstart_Arcbox_docs). While it's not mandatory, it's highly likely that contributors will need to clone both repositories to effectively contribute to Arc Jumpstart.

Before you start, we recommend familiarizing yourself with our comprehensive [contribution guidelines](https://aka.ms/JumpstartContribution). These guidelines outline the standards and practices we follow, ensuring consistency and quality across our documentation.

If you're unsure about your future contribution, don't hesitate to start a [GitHub discussion](https://aka.ms/JumpstartDiscussions). This is a great place to ask questions, share ideas, or get feedback on potential contributions. Our community is here to help and we welcome all levels of experience.

Happy contributing!

## 📥 Cloning the repositories

To contribute, you'll likely need to clone both this repository and the [documentation repository](https://github.com/SQLLord/arc_jumpstart_Arcbox_docs). Use the following commands:

```bash
git clone https://github.com/SQLLord/arc_jumpstart_arcbox.git
git clone https://github.com/SQLLord/arc_jumpstart_Arcbox_docs.git
```

As we continuously improve and expand Arc Jumpstart, we recommend keeping your local clones of the repositories up-to-date. You can do this by pulling the latest changes from the main branch:

```bash
git pull origin main
```

You can use partial clones if you want to reduce the time and size it takes to clone this repository. By default, when you clone this repository, you get all the files and their associated metadata, including blobs and diff history. However, if you don't need all of this information, you can use the following command to clone the repository without the blobs:

```bash
git clone --filter=blob:none https://github.com/SQLLord/arc_jumpstart_arcbox
```

## 🙌 Contribution and feedback

We value your input! If you have suggestions, feedback, or valuable insights to share, feel free to open an issue. Your contributions help us improve the documentation for the entire community.

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit the [Microsoft Contributor License Agreements website](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## 📑 Repository Policies

See [REPO_POLICIES.md](./REPO_POLICIES.md) for details on automated pull request and issue management policies.

## 🏷️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).

Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

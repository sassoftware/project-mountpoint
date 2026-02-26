# ![pmp icon](/images/pmp-icon-40x40.png) PROJECT MOUNTPOINT



Project Mountpoint aims to provide the tools and guidance to streamline configuration of the SAS Viya platform for implementing your choice of storage providers in the Kubernetes environment.

This project contains a collection of utilities and proven practices. For the most part, you can pick and choose the specific functionality you desire. Refer to the appropriate sections as needed.

To get started, refer to [Welcome to Project Mountpoint](/1-Welcome-to-Project-Mountpoint/).



## Releases

SAS releases updates to the Viya platform every month. Those releases - whether LTS or Stable cadence - are versioned `YYYY.MM`. Project Mountpoint will keep pace with a matching release number system.

```bash
# clone the Project Mountpoint git repo
git clone https://your-git-repo.example.com/GEL/utilities/project-mountpoint.git

cd project-mountpoint

# EX) Specify the release tag to match SAS Viya for latest LTS
git checkout 2025.09            # or 2025.09.patch01 if exists
```

> The `main` branch is always the latest release - but it might not be compatible with older releases.
>
> Refer to the [Releases page](https://github.com/sassoftware/project-mountpoint/releases) in case of patch updates.

## Support

This project is supported through the use of Github Issues. Refer to the [SUPPORT](/SUPPORT.md) document for details.

## Contributing

Your input and contributions are welcome. Refer to the [CONTRIBUTING](/CONTRIBUTING.md) document for details.

## License

Except for the the contents of the `/images/exempt` folder, this project is licensed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.txt). Elements in the `/images/exempt` folder are owned by SAS and are not released under an open source license.

SAS and all other SAS Institute Inc. product or service names are registered trademarks or trademarks of SAS Institute Inc. in the USA and other countries. ® indicates USA registration.

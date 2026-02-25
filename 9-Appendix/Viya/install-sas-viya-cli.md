# Install the sas-viya CLI

Project Mountpoint relies on using the SAS Viya Command-Line Interace ("`sas-viya`"). Let's get it installed quickly.

1.  Install the sas-viya CLI and pyviyatools

    ```bash
    # Automation to install pyviyatools and sas-viya CLI with plugins
    bash ${PMP_HOME}/bin/auto-deploy-viya-cli.sh
    ```

    When complete, instructions are provided:

    ```log
    [SUCCESS] === The sas-viya CLI and pyviyatools are installed ===
    [INFO] 
    [INFO] NOTE: Wrapper scripts provided to isolate SSL configuration
    [INFO]  Use: ~/bin/sas-viya    ==> /usr/bin/sas-viya (with its SSL certs)
    [INFO]  Use: ~/bin/pyviyatools ==> /opt/pyviyatools  (with its SSL certs)
    [INFO] 
    [INFO] Next steps:
    [INFO] 1. Source environment: source ~/.bashrc
    [INFO] 2. Create profile: sas-viya profile init
    [INFO] 3. Login: sas-viya auth login
    [INFO] 4. Test pyviyatools: pyviyatools showsetup.py
    ```

1.  Perform those steps. As prompted, respond:

    | Prompt           | Response |
    | ------           | -------- |
    | Service Endpoint | `https://{{ the VIYA_FQDN }}` |
    | Userid           | `sasadm` |
    | Password         | `lnxsas` |

1.  Finally, when you run `python3 showsetup.py`, results should look like:

    ```text
    Python Version is: 3.9
    Requests Version is: 2.25.1
    SAS_CLI_PROFILE environment variable not set, using Default profile
    SSL_CERT_FILE environment variable set to profile /home/cloud-user/.certs/sas-viya-ca.crt
    REQUESTS_CA_BUNDLE environment variable set to profile /home/cloud-user/.certs/sas-viya-ca.crt
    Note your authentication token expires at: 2025-09-05T22:29:45Z
    Endpoint is: https://{{ the VIYA_FQDN }}
    Logged on as id: sasadm
    Logged on as name: SAS Administrator
    THE CLI was found at: /opt/sas/viya/home/bin/sas-viya
    ```

Done.
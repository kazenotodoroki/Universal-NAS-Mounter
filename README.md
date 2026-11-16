# Universal NAS Mounter

A single file you double-click to map a network share (NAS, SMB server) as a Windows drive, on any PC and with any NAS.

The script asks for the address, credentials, share and drive letter, checks each step and explains the most common errors. It works on a local network as well as remotely over a VPN (NetBird, Tailscale, WireGuard…).

## Features

- **Nothing to install**: a single `.cmd` file that uses the PowerShell built into Windows.
- **No administrator rights** required.
- **Connection test** on the SMB port (TCP 445) before asking for credentials, with a 5-second timeout.
- **Hidden password input**, with three attempts.
- **List of shares** available on the NAS, selectable by number.
- **Drive letter choice**, with the first free letter suggested by default, and the option to replace an existing network drive.
- **Reconnect at sign-in** (optional): credentials are stored in Windows Credential Manager.
- **No password written to the file**: the script can be shared or published safely.

## Requirements

- Windows 10 or Windows 11.
- A NAS or server sharing its folders over SMB 2 or SMB 3.
- An account on the NAS **with a password** (Windows 11 blocks guest and passwordless access).
- For remote access: the VPN connected on the PC, with a route or access rule to the NAS.

## Usage

1. Download [`Universal-NAS-Mounter.cmd`](Universal-NAS-Mounter.cmd) (use "Download raw file" on GitHub).
2. Double-click it. If Windows SmartScreen shows a warning, click **More info**, then **Run anyway**.
3. Answer the prompts:

| Step | What is asked | Example |
|---|---|---|
| 1 | NAS IP address or hostname | `192.168.1.100` |
| 2 | Username, then password | `laurent` / `********` |
| 3 | Share to map (number or name) | `1` or `Public` |
| 4 | Drive letter (Enter = suggested one) | `Z` |
| 5 | Reconnect automatically at sign-in | `Y` or `n` |

When it's done, File Explorer opens directly on the new drive.

## Disconnecting a drive

In File Explorer, right-click the drive and choose **Disconnect**. Or, from a command prompt:

```bat
net use Z: /delete
cmdkey /delete:192.168.1.100
```

The second command removes the saved credentials for that NAS.

## Troubleshooting

| Message or symptom | Likely cause | Fix |
|---|---|---|
| "The NAS is not responding on the SMB port (445)" | Wrong address, NAS powered off, VPN disconnected, or port 445 blocked | Check the address and the VPN. In NetBird/Tailscale, the access rule must allow TCP 445. The NAS firewall must accept the VPN range (e.g. `100.64.0.0/10`). |
| Error **1326** | Username or password rejected | On some NAS models (notably WD My Cloud), the network password is separate from the web interface one. Reset the user's password on the NAS. |
| Error **1219** | A connection to the same NAS already exists with another account | Disconnect the drives mapped to that NAS (`net use`) or restart, then run the script again. |
| Error **53** or **67** | NAS or share name not found | Use the IP address instead of the hostname, and check the share name. |
| Connection refused for no clear reason | NAS limited to SMB 1, or no SMB signing support | In the NAS settings, set SMB 2 as the minimum (SMB 3 ideally). Windows 11 24H2 requires SMB signing. |
| The drive doesn't show up in an app run as administrator | Mapped drives are per session (standard / elevated) | Run the app without administrator rights, or run the script from an elevated session. |
| The NAS can't be reached remotely while the PC's local network uses the same subnet as the NAS (e.g. both `192.168.1.x`) | Subnet conflict: Windows looks for the NAS on the local network | Use the NAS's VPN IP (if the VPN runs on the NAS itself), or change the subnet of one of the two networks. |

## How it works

The `.cmd` file contains a PowerShell script after the `:PS1` line. The batch part launches PowerShell, which reads and runs that second part. Mapping relies on standard Windows commands:

- `net use` to test the credentials and map the drive;
- `net view` to list the shares;
- `cmdkey` to store the credentials when automatic reconnection is chosen.

The password only stays in memory while the script runs, and it is masked in error messages.

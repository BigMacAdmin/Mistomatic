# Mistomatic
Utilize mist-cli to automatically keep the latest macOS installers and IPSWs at your fingertips.

This zsh script is designed to be run on a regular interval and will automatically download and store the latest IPSW and DMG for macOS versions 11+.

## Instructions
1. Install Mist-cli: https://github.com/ninxsoft/mist-cli
2. Download Mistomatic.sh and place it anywhere you like.
3. Modify the # User Configuration # section of Mistomatic to fit your environment if necessary.
  4. If you choose to leave the default values, be sure that `/Users/Shared/Mist` exists prior to running.
5. Make the script executable: `chmod +x /path/to/Mistomatic.sh`
6. Run Mistomatic manually at the command line as root/sudo, or setup a LaunchDaemon to run on an interval to always keep your stash up to date.

## How it Works
Mistomatic will use `mist-cli` to generate a plist containing the information for all available DMGs and IPSWs. It will then parse that plist to determine what the latest version of each major macOS release is for each type (installer and IPSW).

Mistomatic will automatically delete outdated installers, and download the latest available versions. If there are two build numbers for the latest version of macOS, then both build numbers will be downloaded and maintained. For example: In June 2023 macOS 13.4.1 was the latest version of macOS, but this version has two build numbers in order to support hardware announced at WWDC2023 (`22F82` and `22F2083`. If there are two build numbers for the latest version of a macOS major release then Mistomatic will IPSWs and DMGs of both builds.

## Additional Details
The `$mistStore` variable in the User Configuration section must point to a directory which already exists. Subfolders for `DMGs` and `IPSWs` will be automatically created. Folders/files created by Mistomatic will grant read writes to all users of the system to avoid issues with root ownership.

`mist-cli` must be run as root, and thus `Mistomatic.sh` must also be run as root.

Script is designed to be either run on demand when you know new builds are available, or initiated via a LaunchDaemon daily/weekly to keep a repository up to date.

## Stretch Goals
I'd like to add a feature for beta support in the future, to keep the latest beta builds of each OS. Let me know if you're using this script and would like to see that added.

#!/bin/zsh
#set -x 

# This script will get the latest versions of macOS 11+ installers in both DMG and IPSW format.
# Older installers for the same major version of macOS will be deleted.
# The intent is to have a script that can be run once a day or once a week in order to ensure
# you have a library of the latest installers for macOS 11, 12, 13, etc.



#########################
#   User Configuration  #
#########################

# This is the oldest macOS major version that we want to look for versions of. Must be 11 or greater.
lowestOS='11'

# This is the newest macOS major version that we want to look for. 
# You can set this higher than existing versions with the only downside being log spam looking for those version numbers
highestOS='15'

# This is the directory path that we are keeping our installers. We'll make sub-directories for DMGs and IPSWs
mistStore='/Users/Shared/Mist'

# Log file path. Leave empty to put output to standard out.
logFile=''

#####################################
# DO NOT EDIT BELOW FOR NORMAL USE  #
#####################################

#############
#   Paths   #
#############

mistPath='/usr/local/bin/mist'
pBuddy='/usr/libexec/PlistBuddy'

plistFile="full.plist"

tmpPlist="/var/tmp/mistomatic-temp_$(date +%s).plist"

#################
#   Functions   #
#################

# Script start time
scriptStartTime=$(date +%s)

function check_root()
{

# check we are running as root
if [[ $(id -u) -ne 0 ]]; then
  echo "ERROR: This script must be run as root **EXITING**"
  exit 1
fi
}

function rm_if_exists()
{
    # A nice function to avoid errors and mistakes
    if [ -n "${1}" ] && [ -e "${1}" ];then
        /bin/rm -rf "${1}"
    fi
}



function no_sleeping()
{
    # Keep device awake while the script is running
    /usr/bin/caffeinate -d -i -m -u &
    caffeinatepid=$!

}

function log_message()
{
    if [ -n "$logFile" ]; then
    	/bin/echo "$(date +%Y-%m-%d_%H:%M:%S): $*" >> "$logFile"
    else
    	/bin/echo "$(date +%Y-%m-%d_%H:%M:%S): $*"
    fi
}

function cleanup_and_exit(){
    ## $1 is the exit code
    ## $2 is the exit message

    # Delete files
    rm_if_exists "/var/tmp/installer_full.plist"
    rm_if_exists "/var/tmp/firmware_full.plist"
    rm_if_exists "$tmpPlist"
    
    # Stop caffeinate
    kill "$caffeinatepid"

    # Timer
    scriptExitTime=$(date +%s)
    scriptRunTimeSeconds=$(( scriptExitTime - scriptStartTime ))
    scriptRunTimeMinutes=$(( scriptRunTimeSeconds / 60 ))
    
    # Announce and exit
    log_message "Exit code: ${1} - Duration: $scriptRunTimeMinutes minutes  ${2}"
    exit "${1}"

}

function validate_prerequisites(){
    # Verify mist-cli is installed
    if [ ! -x "$mistPath" ]; then
        cleanup_and_exit 1 "Mist-CLI does not appear to be installed: $mistPath"
    fi

    # Verify destination directory exists
    if [ ! -e "$mistStore" ]; then
        cleanup_and_exit 1 "Path to installers does not exist. Please create or redefine: $mistStore"
    fi

    # Make DMG and IPSW directories if needed
    if [ ! -d "$mistStore"/DMGs ]; then
        mkdir -p "$mistStore"/DMGs
    fi
    if [ ! -d "$mistStore"/IPSWs ]; then
        mkdir -p "$mistStore"/IPSWs
    fi
    
    # Something bad happened, bail out
    if [ ! -d "$mistStore"/IPSWs ] || [ ! -d "$mistStore"/DMGs ]; then
        cleanup_and_exit 1 "Error creating required directories"
    fi

    # Set permissions so users can easily read
    chmod 755 "$mistStore"/DMGs
    chmod 755 "$mistStore"/IPSWs

    # Sigh, this is dumb but ls /path/*.file throws errors to output even if sent to /dev/null, so here we are making dummy files
    touch "$mistStore"/DMGs/.dummyfile-1234zzz.dmg
    touch "$mistStore"/IPSWs/.dummyfile-1234zzz.ipsw

    # Create a new tmpPlist with some basic values
    "$pBuddy" -c "Add InstallersToDownload array" "$tmpPlist" > /dev/null 2>&1
    "$pBuddy" -c "Add FirmwaresToDownload array" "$tmpPlist" > /dev/null 2>&1

}

function generate_mist_plist(){
    ## Provide argument [ firmware | installer ]
    #This is the plist of the latest builds 
    log_message "Generating $1 Plist"
    mistPlist="/var/tmp/${1}_full.plist"
    "$mistPath" list "$1" --export "$mistPlist" > /dev/null 2>&1
    chown 655 "$mistPlist"
}

function determine_latest_version(){
    ## Usage:
    ## $1 is the version of macOS you want to determine the latest release for
    ## $2 is either [ firmware | installer ]
    
    # Set index to 0 and we will loop through every dictionary of the array in the plist
    count=0

    # While loop until PlistBuddy exits with an error trying to read the index of the array
    while currentVersionCheck=$("$pBuddy" -c "Print $count:version" "/var/tmp/${2}_$plistFile") > /dev/null 2>&1; do
        # Get the major version of the dictionary we're looking at
        currentMajorVersionCheck=$(echo "$currentVersionCheck" | cut -d '.' -f 1)
        # If the current item we're looking at is of the expected major version, then
        if [ $currentMajorVersionCheck = ${1} ]; then
            # Add the build number to the array of what we want to download
            if [ ${2} = "firmware" ]; then
                "$pBuddy" -c "Add :FirmwaresToDownload: string $($pBuddy -c "Print $count:build" /var/tmp/${2}_$plistFile)" "$tmpPlist"
            elif [ ${2} = "installer" ]; then
                "$pBuddy" -c "Add :InstallersToDownload: string $($pBuddy -c "Print $count:build" /var/tmp/${2}_$plistFile)" "$tmpPlist"
            fi

            # Now check if there is more than one item with the same version number. 
            # This happens when Apple releases two builds of the same major version (like when new hardware releases in the middle of an OS lifecycle.)
            # In the interest of keeping my sanity, I'm limiting this to two build versions of the same OS. If Apple for some reason releases three builds of the same OS, this will break.
            # I grow old … I grow old … I shall wear the bottoms of my trousers rolled.
            testCount=$(( count + 1 ))

            # If the next entry in the index is valid, then
            if testVersion=$("$pBuddy" -c "Print $testCount:version" "/var/tmp/${2}_$plistFile" ) > /dev/null 2>&1; then
                # If this entry has the same value as the preceding version"
                if [ "$currentVersionCheck" = $testVersion ]; then
                    # Add the build do the array of builds we want to download
                    if [ ${2} = "firmware" ]; then
                        "$pBuddy" -c "Add :FirmwaresToDownload: string $($pBuddy -c "Print $testCount:build" /var/tmp/${2}_$plistFile)" "$tmpPlist"
                    elif [ ${2} = "installer" ]; then
                        "$pBuddy" -c "Add :InstallersToDownload: string $($pBuddy -c "Print $testCount:build" /var/tmp/${2}_$plistFile)" "$tmpPlist"
                    fi
                fi
            break
            fi
        fi
        # Increase the index and do it all again...
        count=$(( count + 1 ))
    done

}

function process_directory_dmg(){
    # This function deletes items from the DMGs folder, unless they've been identified as a build number we want to keep.
    # If there is a file in DMGs
    if ls "$mistStore"/DMGs/*.dmg > /dev/null 2>&1; then
        # For every DMG in the DMGs directory, 
        for existingItem in "$mistStore"/DMGs/*.dmg; do
            # Get the filename by itself
            existingItemFilename=$(basename "${existingItem}")
            # Get the Build number by parsing the filename
            existingItemBuild=$(basename ${existingItem:r} | cut -d '-' -f 2 )

            # If the build number is in our array of desired installers
            # Found this trick here and modified it for my purposes: https://technology.siprep.org/using-plistbuddy-to-delete-a-string-from-an-array/
            if removeBuildIndex=$("$pBuddy" -c "Print :InstallersToDownload" "$tmpPlist" | grep -n "$existingItemBuild" | /usr/bin/awk -F ":" '{print $1}') && [ -n "$removeBuildIndex" ]; then
                log_message "DMG already found: $existingItemBuild"
                removeBuildIndex=$(( removeBuildIndex - 2 ))
                "$pBuddy" -c "Delete InstallersToDownload:$removeBuildIndex" "$tmpPlist"
            else
            # We have identified an outdated DMG, delete it
            log_message "Deleting outdated DMG: ${mistStore}/DMGs/${existingItemFilename}"
            rm_if_exists "${mistStore}/DMGs/${existingItemFilename}"
            fi
        done
    fi
}

function process_directory_ipsw(){
    # This function deletes items from the IPSWs folder, unless they've been identified as a build number we want to keep.
    
    # If there is a file in IPSWs
    if ls "$mistStore"/IPSWs/*.ipsw > /dev/null 2>&1; then
        # For every DMG in the IPSWs directory, 
        for existingItem in "$mistStore"/IPSWs/*.ipsw; do
            # Get the filename by itself
            existingItemFilename=$(basename "${existingItem}")
            # Get the Build number by parsing the filename
            existingItemBuild=$(basename ${existingItem:r} | cut -d '-' -f 2 )

            # If the build number is in our array of desired installers
            # Found this trick here and modified it for my purposes: https://technology.siprep.org/using-plistbuddy-to-delete-a-string-from-an-array/
            if removeBuildIndex=$("$pBuddy" -c "Print :FirmwaresToDownload" "$tmpPlist" | grep -n "$existingItemBuild" | /usr/bin/awk -F ":" '{print $1}') && [ -n "$removeBuildIndex" ]; then
                log_message "IPSW already found: $existingItemBuild"
                removeBuildIndex=$(( removeBuildIndex - 2 ))
                "$pBuddy" -c "Delete FirmwaresToDownload:$removeBuildIndex" "$tmpPlist"
            else
            # We have identified an outdated IPSW, delete it
            log_message "Deleting outdated IPSW: ${mistStore}/IPSWs/${existingItemFilename}"
            rm_if_exists "${mistStore}/IPSWs/${existingItemFilename}"
            fi
        done
    fi
}

download_things(){
    ## Requires an argument
    ## $1 is the name of the plist array for the items you want to download

    # Timer
    downloadStartTime=$(date +%s)
    # Index
    downloadCount=0

    # Loop through the index of things to download
    while thingToDownload=$("$pBuddy" -c "Print $1:$downloadCount" "$tmpPlist")  > /dev/null 2>&1 ; do
        # Set variables for Firmware scenario
        if [ "$1" = "FirmwaresToDownload" ]; then
            type="firmware"
            destinationDir="$mistStore/IPSWs"
            image=''
        # Set variables for Installer scenario
        elif [ "$1" = "InstallersToDownload" ]; then
            type="installer"
            destinationDir="$mistStore/DMGs"
            image='image'
        else
            # This is only reachable if the function is being used wrong.
            cleanup_and_exit 1 "***ERROR using download_things function. Check your script.***"
        fi
        
        # Initiate the actual download of the item being processed
        log_message "Initiating Download: $mistPath download $type $thingToDownload $image -o $destinationDir"
        if "$mistPath" download "$type" "$thingToDownload" $image -o "$destinationDir" > /dev/null 2>&1; then 
            # Report successful item
            downloadFinishTime=$(date +%s)
            downloadDurationSeconds=$(( downloadFinishTime - downloadStartTime ))
            downloadDurationMinutes=$(( downloadDurationSeconds / 60 ))
            log_message "Successful download: $type $thingToDownload Duration: $downloadDurationMinutes minutes"
        else
            # Mist exited with an error code.
            log_message "***WARNING: Mist exited with an error code. Failed to download: $type $thingToDownload"
        fi
        # Increase the index and do it again...
        downloadCount=$(( downloadCount +1 ))
    done
}

#########################
#   Script Starts Here  #
#########################

check_root

no_sleeping

validate_prerequisites

generate_mist_plist firmware

generate_mist_plist installer

# Start an index for macOS releases we're checking
checkingForOS="$lowestOS"

# Do logic for latest version of each macOS release we're checking
log_message "Identifying latest build of macOS $lowestOS to $highestOS"
while [ $checkingForOS -le $highestOS ]; do
    determine_latest_version $checkingForOS firmware
    determine_latest_version $checkingForOS installer
    checkingForOS=$(( checkingForOS +1 ))
done

# Check for existing dmgs/ipsws and delete if needed
process_directory_dmg
process_directory_ipsw

# Download all the things!
download_things InstallersToDownload
download_things FirmwaresToDownload

# fin
cleanup_and_exit 0 "Script Completed Successfully"

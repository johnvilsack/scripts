serial=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $NF}')
name="JV-$serial"

sudo scutil --set ComputerName "$name"
sudo scutil --set HostName "$name"
sudo scutil --set LocalHostName "$name"


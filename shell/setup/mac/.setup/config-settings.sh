# Tap to Click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Disable Natural Scrolling
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

# Disable Zoom Gesture
defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadPinch -bool false

# Disable Smart Zoom
defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerDoubleTapGesture -int 0

# Disable Rotate Gesture
defaults write com.apple.AppleMultitouchTrackpad TrackpadRotate -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRotate -bool false

# Enable Control Zoom Scrolling
# sudo defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
# sudo defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144

# Hide Spotlight Icon
defaults write com.apple.controlcenter 'NSStatusItem Visible Siri' -bool true
defaults write com.apple.controlcenter 'NSStatusItem Visible Spotlight' -bool false

# Dark Mode
defaults write -g AppleInterfaceStyle -string "Dark"

# Set wallpaper to black
osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/System/Library/Desktop Pictures/Solid Colors/black.png"'

# Dock Settings
defaults write com.apple.dock orientation -string left
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.WindowManager EnableStageManagerClickWallpaperToRevealDesktop -bool true
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false


# Set bottom-right hot corner (corner 4) to Lock Screen (action 13)
defaults write com.apple.dock wvous-br-corner -int 13
defaults write com.apple.dock wvous-br-modifier -int 0

# Enable Night Shift automatic schedule (sunrise to sunset)
# defaults write com.apple.CoreBrightness CBBlueReductionAutoScheduleEnabled -bool true
# defaults write com.apple.CoreBrightness CBBlueReductionScheduleType -int 1

## Spotlight
# defaults write com.apple.spotlight orderedItems -array \
#   '{"enabled" = 1; "name" = "APPLICATIONS";}' \
#   '{"enabled" = 1; "name" = "SYSTEM_PREFS";}' \
#   '{"enabled" = 1; "name" = "MENU_DEFINITION";}' \
#   '{"enabled" = 1; "name" = "MENU_CONVERSION";}' \
#   '{"enabled" = 1; "name" = "MENU_EXPRESSION";}'

# Disable indexing for common content folders
# sudo mdutil -i off ~/Documents
# sudo mdutil -i off ~/Downloads
# sudo mdutil -i off ~/Pictures
# sudo mdutil -i off ~/Music
# sudo mdutil -i off ~/Movies
# sudo mdutil -i off ~/Library/Mail
# sudo mdutil -i off ~/Library/Calendars
# sudo mdutil -i off ~/Library/Contacts
# sudo mdutil -i off /Library/Fonts

# Disable Improving Search
# defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2
# defaults write com.apple.assistant.support "Assistant Enabled" -bool false
# defaults write com.apple.assistant.support "SiriServerLoggingEnabled" -bool false

# Fastest key repeat rate
defaults write -g KeyRepeat -int 1

# Shortest delay before key repeat starts
defaults write -g InitialKeyRepeat -int 10

## SOFTWARE UPDATES 

# 1. Automatically check for updates
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

# 2. Download new updates when available
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true

# 3. Install macOS updates (system data files & security updates)
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

# 4. Install app updates from the App Store
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true

sudo mdutil -E /
killall mds > /dev/null 2>&1; sudo mdutil -E /
sudo softwareupdate --schedule on
killall SystemUIServer
killall Dock

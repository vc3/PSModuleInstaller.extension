# Change Log
All notable changes to this project will be documented in [this file](http://keepachangelog.com/).
This project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.1] - 2017-09-22
### Added
- Minor logging additions/tweaks
### Fixed
- Fix issue with `Expand-ModulePackage` command

## [0.2.0] - 2017-09-22
### Added
- Support installing from local directory path
- Include install date in `.chocolateyInstall` metadata file
### Fixed
- Don't use version directory for verisons of PowerShell prior to v5
- Fix issues with removal of extra files from nupkg file
- Fix minor verbose logging issues

## [0.1.0] - 2017-06-20
### Added
- Initial version of `Install-ChocolateyPowerShellModule` and `Uninstall-ChocolateyPowerShellModule`.

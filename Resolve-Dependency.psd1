@{
    Gallery                                     = 'PSGallery'
    AllowPrerelease                             = $false
    WithYAML                                    = $true # Will also bootstrap PowerShell-Yaml to read other config files

    # Resolve dependencies with PSResourceGet into output\RequiredModules only (no ModuleFast).
    UsePSResourceGet                            = $true
    PSResourceGetVersion                        = '1.0.1'
    UsePowerShellGetCompatibilityModule         = $true
    UsePowerShellGetCompatibilityModuleVersion  = '3.0.23-beta23'
}

@{
    # PSDependOptions is ignored by PSResourceGet.
    #PSDependOptions             = @{
    #    AddToPath  = $true
    #    Target     = 'output\RequiredModules'
    #    Parameters = @{
    #        Repository = 'PSGallery'
    #    }
    #}

    # Build engine that runs the tasks in build.yaml.
    InvokeBuild                 = '5.14.23'
    # Static analysis used by the QA tests.
    PSScriptAnalyzer            = '1.25.0'
    # Latest Pester 5.x; Pester 6 is not used by the tests.
    Pester                      = '5.9.1'
    # Scaffolding used by Sampler.
    Plaster                     = '2.1.5'
    # Compiles the source folder into the module.
    ModuleBuilder               = '3.2.18'
    # Reads and updates CHANGELOG.md.
    ChangelogManagement         = '3.1.0'
    # Build tasks and helpers for the module.
    Sampler                     = '0.120.1'
    # GitHub release tasks for Sampler.
    'Sampler.GitHubTasks'       = '0.5.0'
    # Checks links in the markdown files.
    MarkdownLinkCheck           = '0.2.0'

    # ModuleBuilder dependency, listed because PSResourceGet 1.0.1 does not install
    # transitive RequiredModules during the bootstrap.
    Configuration               = '1.6.0'
    # ModuleBuilder dependency, listed for the same reason.
    Metadata                    = '1.5.7'
    # Sampler.GitHubTasks dependency, listed for the same reason.
    PowerShellForGitHub         = '0.17.0'
}

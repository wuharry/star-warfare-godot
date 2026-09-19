param(
    [Parameter(Mandatory=$true)][string]$Assembly,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Cecil = 'C:/Program Files/Unity/Hub/Editor/6000.1.10f1/Editor/Data/il2cpp/build/deploy/Mono.Cecil.dll'
)
$ErrorActionPreference = 'Stop'
# Cecil reads metadata and IL; it never loads or executes the game's assembly.
[void][Reflection.Assembly]::LoadFrom($Cecil)
$definition = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Resolve-Path -LiteralPath $Assembly).Path)
$writer = [IO.StreamWriter]::new([IO.Path]::GetFullPath($Output), $false, [Text.UTF8Encoding]::new($false))
function Write-Type($type) {
    $writer.WriteLine("TYPE $($type.FullName) : $($type.BaseType)")
    foreach ($field in $type.Fields) {
        $writer.WriteLine("  FIELD $($field.FullName) = $($field.Constant)")
    }
    foreach ($method in $type.Methods) {
        $writer.WriteLine("  METHOD $($method.FullName)")
        if ($method.HasBody) {
            foreach ($instruction in $method.Body.Instructions) {
                $writer.WriteLine("    $instruction")
            }
        }
    }
    foreach ($child in $type.NestedTypes) { Write-Type $child }
}
try {
    foreach ($type in $definition.MainModule.Types) { Write-Type $type }
} finally {
    $writer.Dispose()
    $definition.Dispose()
}
Write-Output "MANAGED_METADATA_EXPORTED $Output"

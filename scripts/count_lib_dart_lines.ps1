Set-Location 'C:\code\Flutter\kira'

Get-ChildItem -LiteralPath .\lib -Recurse -Filter *.dart |
Where-Object { $_.FullName -notmatch '\\l10n\\' } |
ForEach-Object {
  $content = Get-Content -LiteralPath $_.FullName
  [PSCustomObject]@{
    Lines = $content.Count
    File  = $_.FullName.Substring((Resolve-Path .).Path.Length + 1)
  }
} |
Sort-Object Lines -Descending |
Format-Table -AutoSize

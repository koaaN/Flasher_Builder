@echo off
setlocal

set "input=%~dp0dtbo.img"
set "output=%~dp0dtbo_patched.img"

copy "%input%" "%output%" >nul

powershell -Command ^
  "$bytes = [System.IO.File]::ReadAllBytes('%output%');" ^
  "$search = [System.Text.Encoding]::ASCII.GetBytes('oplus,hmbird');" ^
  "$replace = [System.Text.Encoding]::ASCII.GetBytes('oplus,xxbird');" ^
  "for ($i = 0; $i -le $bytes.Length - $search.Length; $i++) {" ^
  "  $match = $true;" ^
  "  for ($j = 0; $j -lt $search.Length; $j++) {" ^
  "    if ($bytes[$i + $j] -ne $search[$j]) { $match = $false; break }" ^
  "  }" ^
  "  if ($match) { for ($j = 0; $j -lt $replace.Length; $j++) { $bytes[$i + $j] = $replace[$j] }; break }" ^
  "}" ^
  "[System.IO.File]::WriteAllBytes('%output%', $bytes)"

echo dtbo patched successfully!
echo Saved as %output%
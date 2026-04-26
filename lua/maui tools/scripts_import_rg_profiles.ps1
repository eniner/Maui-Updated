param(
  [string]$CorpusRoot = 'C:\Users\E9ine\Desktop\MQ Helper Overlay\redguides\www.redguides.com\community\resources',
  [string]$TemplatesRoot = 'C:\Users\E9ine\AppData\Local\VeryVanilla\Emu\Release\config\UltimateEQAssist\Templates\ImportedRG'
)

$ErrorActionPreference = 'Stop'

if(-not (Test-Path $CorpusRoot)) { throw "Corpus root not found: $CorpusRoot" }
if(Test-Path $TemplatesRoot){ Remove-Item -Recurse -Force $TemplatesRoot }
New-Item -ItemType Directory -Force -Path $TemplatesRoot | Out-Null

$ClassPatterns = @(
  @{ Code='BER'; Pattern='berserker|\bber\b|\bzerk' }, @{ Code='BRD'; Pattern='bard|\bbrd\b' },
  @{ Code='BST'; Pattern='beastlord|\bbst\b' }, @{ Code='CLR'; Pattern='cleric|\bclr\b' },
  @{ Code='DRU'; Pattern='druid|\bdru\b' }, @{ Code='ENC'; Pattern='enchanter|\benc\b' },
  @{ Code='MAG'; Pattern='magician|\bmage\b|\bmag\b' }, @{ Code='MNK'; Pattern='monk|\bmnk\b' },
  @{ Code='NEC'; Pattern='necromancer|necro|\bnec\b' }, @{ Code='PAL'; Pattern='paladin|\bpally\b|\bpal\b' },
  @{ Code='RNG'; Pattern='ranger|\brng\b' }, @{ Code='ROG'; Pattern='rogue|\brog\b' },
  @{ Code='SHD'; Pattern='shadow-?knight|\bsk\b' }, @{ Code='SHM'; Pattern='shaman|\bshm\b' },
  @{ Code='WAR'; Pattern='warrior|\bwar\b' }, @{ Code='WIZ'; Pattern='wizard|\bwiz\b' }
)

function Get-ClassCode([string]$name){
  $n = $name.ToLowerInvariant()
  foreach($c in $ClassPatterns){ if($n -match $c.Pattern){ return $c.Code } }
  return $null
}

function Get-Level([string]$name){
  $base = ($name.ToLowerInvariant() -split '\.')[0]
  $tokens = $base -split '[-_]'
  $valid = @('5','10','15','20','25')

  if($tokens.Count -gt 0 -and $valid -contains $tokens[0]){ return [int]$tokens[0] }

  for($i=0; $i -lt $tokens.Count - 1; $i++){
    if($tokens[$i] -eq 'level' -or $tokens[$i] -eq 'lvl'){
      if($valid -contains $tokens[$i+1]){ return [int]$tokens[$i+1] }
    }
  }

  if($tokens.Count -gt 1 -and $valid -contains $tokens[1]){ return [int]$tokens[1] }
  return $null
}

function Score-Name([string]$name){
  $n = $name.ToLowerInvariant(); $score = 0
  if($n -match 'maximum-effort'){ $score += 80 }
  if($n -match 'muleassist'){ $score += 40 }
  if($n -match 'kiss'){ $score += 20 }
  if($n -match 'live'){ $score += 10 }
  if($n -match 'working-on|wip|experimental'){ $score -= 20 }
  if($n -match 'no-conditions|w-o-conditions'){ $score -= 6 }
  return $score
}

function Decode-IniFromFile([string]$file){
  $raw = Get-Content -Path $file -Raw
  $m = [regex]::Match($raw, '"description"\s*:\s*"(?<desc>\[General\].*?)"\s*,', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if(-not $m.Success){ return $null }
  $esc = $m.Groups['desc'].Value
  try {
    $obj = ('{"v":"' + $esc + '"}') | ConvertFrom-Json
    $decoded = [string]$obj.v
  } catch { return $null }
  if([string]::IsNullOrWhiteSpace($decoded)){ return $null }
  if($decoded -notmatch '\[DPS\]' -and $decoded -notmatch '\[Buffs\]'){ return $null }
  return $decoded
}

$candidates = @{}
$dirs = Get-ChildItem -Path $CorpusRoot -Directory
foreach($d in $dirs){
  $lvl = Get-Level $d.Name; if($null -eq $lvl){ continue }
  $cls = Get-ClassCode $d.Name; if($null -eq $cls){ continue }

  $file = $null
  $f1 = Join-Path $d.FullName 'index.html'; $f2 = Join-Path $d.FullName 'index.html.tmp'
  if(Test-Path $f1){ $file = $f1 } elseif(Test-Path $f2){ $file = $f2 }
  if($null -eq $file){ continue }

  $ini = Decode-IniFromFile $file; if($null -eq $ini){ continue }

  $score = Score-Name $d.Name
  $key = "$lvl|$cls"
  $obj = [pscustomobject]@{ Level=$lvl; Class=$cls; Name=$d.Name; Score=$score; File=$file; Ini=$ini }

  if(-not $candidates.ContainsKey($key)){
    $candidates[$key] = $obj
  } else {
    $cur = $candidates[$key]
    if($obj.Score -gt $cur.Score -or ($obj.Score -eq $cur.Score -and $obj.Name.Length -lt $cur.Name.Length)){
      $candidates[$key] = $obj
    }
  }
}

$written = 0
$groups = @('GROUP','SOLO','RAID')
$selectionRows = New-Object System.Collections.Generic.List[string]

foreach($entry in $candidates.Values | Sort-Object Level,Class){
  $levelDir = Join-Path $TemplatesRoot ("Level{0}" -f $entry.Level)
  $presetsDir = Join-Path $levelDir 'Presets'
  $kahybridDir = Join-Path $levelDir 'KAHybrid'
  New-Item -ItemType Directory -Force -Path $presetsDir | Out-Null
  New-Item -ItemType Directory -Force -Path $kahybridDir | Out-Null

  $header = @('; ImportedRG generated from RedGuides corpus', ('; Source: {0}' -f $entry.Name), ('; Source File: {0}' -f $entry.File), ';') -join "`r`n"
  $body = ($entry.Ini -replace "`n", "`r`n")
  $full = $header + "`r`n" + $body + "`r`n"

  foreach($mode in $groups){
    $base = "UltimateEQAssist_L{0}_{1}_{2}" -f $entry.Level, $entry.Class, $mode
    Set-Content -Path (Join-Path $presetsDir ("$base.ini")) -Value $full -Encoding UTF8
    Set-Content -Path (Join-Path $kahybridDir ("{0}_KAHYBRID.ini" -f $base)) -Value $full -Encoding UTF8
    $written += 2
  }

  Set-Content -Path (Join-Path $levelDir ("UltimateEQAssist_L{0}_{1}.ini" -f $entry.Level, $entry.Class)) -Value $full -Encoding UTF8
  $written += 1

  $selectionRows.Add(("L{0} {1} <- {2} (score {3})" -f $entry.Level, $entry.Class, $entry.Name, $entry.Score)) | Out-Null
}

"pairs_selected=$($candidates.Count)"
"files_written=$written"
$selectionRows | Select-Object -First 150


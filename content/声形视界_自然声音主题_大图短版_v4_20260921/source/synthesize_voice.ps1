param([Parameter(Mandatory=$true)][string]$AssetRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $synth.SelectVoice('Microsoft Huihui Desktop')
    $synth.Rate = 0
    $synth.Volume = 100
    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
    $clips = Get-Content -LiteralPath (Join-Path $AssetRoot 'source/speech.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($clip in $clips) {
        $wavPath = Join-Path $AssetRoot ('source/voice/' + $clip.id + '.wav')
        $synth.SetOutputToWaveFile($wavPath, $format)
        $synth.Speak([string]$clip.text)
        $synth.SetOutputToNull()
    }
} finally { $synth.Dispose() }
Write-Output 'Local Mandarin narration generated.'

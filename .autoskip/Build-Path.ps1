# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
function Get-UniqueBuildPath {
    param([string[]]$Paths)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = foreach ($value in $Paths) {
        foreach ($entry in ($value -split ';')) {
            $entry = $entry.Trim().Trim('"')
            if ($entry -and $seen.Add($entry.TrimEnd('\', '/'))) { $entry }
        }
    }
    $entries -join ';'
}

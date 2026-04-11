# Simple Icon Generator using PowerShell + .NET
# Generates basic colored icons for MindTwin patient and therapist apps

Add-Type -AssemblyName System.Drawing

$iconPath = Join-Path $PSScriptRoot "assets\icon"
if (-not (Test-Path $iconPath)) {
    New-Item -ItemType Directory -Path $iconPath -Force | Out-Null
}

function Create-SimpleIcon {
    param(
        [string]$OutputPath,
        [string]$BackgroundColor,
        [string]$Text,
        [string]$TextColor = "#FFFFFF",
        [int]$Size = 1024
    )
    
    try {
        # Create bitmap
        $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        # Parse colors
        $bgColor = [System.Drawing.ColorTranslator]::FromHtml($BackgroundColor)
        $txtColor = [System.Drawing.ColorTranslator]::FromHtml($TextColor)
        
        # Fill background
        $brush = New-Object System.Drawing.SolidBrush($bgColor)
        $graphics.FillRectangle($brush, 0, 0, $Size, $Size)
        
        # Draw text
        $font = New-Object System.Drawing.Font("Arial", ($Size / 3), [System.Drawing.FontStyle]::Bold)
        $textBrush = New-Object System.Drawing.SolidBrush($txtColor)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
        
        $graphics.DrawString($Text, $font, $textBrush, $rect, $format)
        
        # Save
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        
        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $brush.Dispose()
        $textBrush.Dispose()
        $font.Dispose()
        
        Write-Host "Created: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error creating icon: $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "Generating MindTwin app icons..." -ForegroundColor Cyan
Write-Host ""

# Generate main icon (unified - purple/indigo mix)
$mainIcon = Join-Path $iconPath "app_icon.png"
Create-SimpleIcon -OutputPath $mainIcon -BackgroundColor "#5C6BC0" -Text "MT"

# Generate foreground for adaptive icon
$fgIcon = Join-Path $iconPath "app_icon_foreground.png"
# For foreground, we'll create with transparent background
# Note: Simple version still uses solid bg, user should replace with proper transparent PNG
Create-SimpleIcon -OutputPath $fgIcon -BackgroundColor "#5C6BC0" -Text "MT"

Write-Host ""
Write-Host "Icon generation complete!" -ForegroundColor Green
Write-Host "Generated files:" -ForegroundColor Yellow
Write-Host "  - $mainIcon"
Write-Host "  - $fgIcon"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Run: flutter pub get"
Write-Host "2. Run: flutter pub run flutter_launcher_icons"
Write-Host "3. Rebuild APKs"
Write-Host ""
Write-Host "For better icons, replace these files with professional designs." -ForegroundColor Yellow

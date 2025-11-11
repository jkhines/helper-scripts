param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationImageUri
)

# FUNCTIONS ----------------------------------------------------------
function Get-DestinationEcrUriParts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageUri
    )

    # Support either digest or tag URIs, e.g.:
    # - 123456789012.dkr.ecr.us-west-2.amazonaws.com/repo@sha256:abcdef...
    # - 123456789012.dkr.ecr.us-west-2.amazonaws.com/repo:my-tag

    $patternDigest = '^(?<registryId>\d{12})\.dkr\.ecr\.(?<region>[a-z0-9-]+)\.amazonaws\.com/(?<repository>[a-z0-9._/\-]+)@(?<digest>sha256:[A-Fa-f0-9]{64})$'
    $patternTag    = '^(?<registryId>\d{12})\.dkr\.ecr\.(?<region>[a-z0-9-]+)\.amazonaws\.com/(?<repository>[a-z0-9._/\-]+):(?<tag>[A-Za-z0-9][A-Za-z0-9_.\-]{0,127})$'

    $m = [regex]::Match($ImageUri, $patternDigest)
    if ($m.Success) {
        return [pscustomobject]@{
            RegistryId = $m.Groups['registryId'].Value
            Region     = $m.Groups['region'].Value
            Repository = $m.Groups['repository'].Value
            Digest     = $m.Groups['digest'].Value
            Tag        = $null
        }
    }

    $m = [regex]::Match($ImageUri, $patternTag)
    if ($m.Success) {
        return [pscustomobject]@{
            RegistryId = $m.Groups['registryId'].Value
            Region     = $m.Groups['region'].Value
            Repository = $m.Groups['repository'].Value
            Digest     = $null
            Tag        = $m.Groups['tag'].Value
        }
    }

    throw "Invalid destination image URI format: $ImageUri. Expected account.dkr.ecr.region.amazonaws.com/repository@sha256:<64-hex> or account.dkr.ecr.region.amazonaws.com/repository:tag."
}

try {
    # Parse destination details (registry, region, repo, digest/tag).
    $dest = Get-DestinationEcrUriParts -ImageUri $DestinationImageUri

    if ($dest.Digest) {
        Write-Host "Retagging 'latest' in repository '$($dest.Repository)' (region '$($dest.Region)') to point to digest '$($dest.Digest)'."
    } elseif ($dest.Tag) {
        Write-Host "Retagging 'latest' in repository '$($dest.Repository)' (region '$($dest.Region)') to point to tag '$($dest.Tag)'."
    }

    # Resolve destination digest if a tag was provided.
    $TargetDigest = $dest.Digest
    if ([string]::IsNullOrWhiteSpace($TargetDigest)) {
        Write-Host "Resolving digest for tag '$($dest.Tag)'."
        $TargetDigest = aws ecr batch-get-image `
            --region $dest.Region `
            --registry-id $dest.RegistryId `
            --repository-name $dest.Repository `
            --image-ids imageTag=$($dest.Tag) `
            --query 'images[0].imageId.imageDigest' `
            --output text

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($TargetDigest)) {
            throw "Failed to resolve digest for tag '$($dest.Tag)'."
        }
    }

    # 1) Capture the current digest behind 'latest' (source) before changing it.
    Write-Host "Retrieving current digest for tag 'latest'."
    $SourceLatestDigest = $null
    $SourceLatestDigest = aws ecr batch-get-image `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-ids imageTag=latest `
        --query 'images[0].imageId.imageDigest' `
        --output text 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($SourceLatestDigest)) {
        Write-Host "Note: No existing 'latest' tag found in the repository or retrieval failed. Continuing."    
        $SourceLatestDigest = $null
    }

    # 2) Does destination image already have the 'latest' tag?
    $destTags = aws ecr describe-images `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-ids imageDigest=$($TargetDigest) `
        --query 'imageDetails[0].imageTags' `
        --output text 2>$null

    if ($LASTEXITCODE -eq 0 -and $destTags -and $destTags -match '(^|\s)latest(\s|$)') {
        Write-Host "'latest' already points to the destination digest. No changes made."
        return
    }

    # 3) Remove the existing 'latest' tag (if any) to avoid ImageAlreadyExistsException.
    Write-Host "Removing any existing 'latest' tag in the repository (if present)"
    aws ecr batch-delete-image `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-ids imageTag=latest 2>$null
    # ignore failures if tag didn't exist.

    # 4) Retrieve manifest **and media type** for the destination digest.
    Write-Host "Retrieving manifest & media type for destination digest: $($TargetDigest)"

    $MediaType = aws ecr describe-images `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-ids imageDigest=$($TargetDigest) `
        --query 'imageDetails[0].imageManifestMediaType' `
        --output text

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($MediaType)) {
        throw "Failed to retrieve media type for destination digest $($TargetDigest)."
    }

    # Pull the full JSON so we can validate the returned digest matches the requested digest.
    $batchJson = aws ecr batch-get-image `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-ids imageDigest=$($TargetDigest) `
        --accepted-media-types $MediaType `
        --output json

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($batchJson)) {
        throw "Failed to retrieve manifest JSON for destination digest $($TargetDigest)."
    }

    $batch = $null
    try { $batch = $batchJson | ConvertFrom-Json } catch {}
    if (-not $batch -or -not $batch.images -or $batch.images.Count -lt 1) {
        throw "Destination image not found when fetching manifest for digest $($TargetDigest)."
    }

    $returnedDigest = $batch.images[0].imageId.imageDigest
    $Manifest = $batch.images[0].imageManifest

    if ([string]::IsNullOrWhiteSpace($Manifest)) {
        throw "Empty manifest retrieved for destination digest $($TargetDigest)."
    }

    if ($returnedDigest -ne $TargetDigest) {
        Write-Host "Warning: Retrieved manifest digest ($returnedDigest) does not match requested digest ($($TargetDigest)). Using the retrieved manifest as source of truth."
    }

    # 5) Tag the destination digest as 'latest'. Use media type to preserve digest. Avoid BOM.
    Write-Host "Applying manifest to tag 'latest' with media type '$MediaType'"
    $tmpManFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmpManFile -Value $Manifest -Encoding utf8NoBOM -NoNewline

    aws ecr put-image `
        --region $dest.Region `
        --registry-id $dest.RegistryId `
        --repository-name $dest.Repository `
        --image-tag latest `
        --image-manifest file://$tmpManFile `
        --image-manifest-media-type $MediaType

    Remove-Item -Path $tmpManFile -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tag 'latest' with destination image manifest."
    }

    Write-Host "Successfully tagged 'latest' to digest $TargetDigest."

} catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
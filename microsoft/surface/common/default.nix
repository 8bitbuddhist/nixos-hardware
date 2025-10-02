{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkDefault
    mkOption
    types
    versions
    ;

  # Kernel source version
  srcVersion =
    with config.hardware.microsoft-surface;
    if kernelVersion == "longterm" then
      "6.12.19"
    else if kernelVersion == "stable" then
      "6.16.10"
    else
      abort "Invalid kernel version: ${kernelVersion}";

  # Kernel source hash
  srcHash =
    with config.hardware.microsoft-surface;
    if kernelVersion == "longterm" then
      "sha256-1zvwV77ARDSxadG2FkGTb30Ml865I6KB8y413U3MZTE="
    else if kernelVersion == "stable" then
      "sha256-qwa7qIUeS2guiDT2+Q5W0y3PmNjGLNU3Z2EEz9dXqPI="
    else
      abort "Invalid kernel version: ${kernelVersion}";

  # linux-surface version
  pkgVersion =
    with config.hardware.microsoft-surface;
    if kernelVersion == "longterm" then
      "6.12.7"
    else if kernelVersion == "stable" then
      "6.16.10"
    else
      abort "Invalid kernel version: ${kernelVersion}";

  # linux-surface hash
  pkgHash =
    with config.hardware.microsoft-surface;
    if kernelVersion == "longterm" then
      "sha256-Pv7O8D8ma+MPLhYP3HSGQki+Yczp8b7d63qMb6l4+mY="
    else if kernelVersion == "stable" then
      "sha256-grZY2DvEjRrr55D9Ov3I5NpXjgxB7z6bYn8K7iO8fOk="
    else
      abort "Invalid kernel version: ${kernelVersion}";

  # linux-surface commit
  pkgRev = with config.hardware.microsoft-surface;
    if kernelVersion == "longterm" then
      "arch-${pkgVersion}-1"
    else if kernelVersion == "stable" then
      "94217c2dc8818afd2296c3776223fc1c093f78fb"
    else
      abort "Invalid kernel version: ${kernelVersion}";

  # Fetch the linux-surface repository
  repos =
    pkgs.callPackage
      (
        {
          fetchFromGitHub,
          rev,
          hash,
        }:
        {
          linux-surface = fetchFromGitHub {
            owner = "linux-surface";
            repo = "linux-surface";
            rev = rev;
            hash = hash;
          };
        }
      )
      {
        hash = pkgHash;
        rev = pkgRev;
      };

  # Fetch and build the kernel source after applying the linux-surface patches
  inherit (pkgs.callPackage ./kernel/linux-package.nix { inherit repos; })
    linuxPackage
    surfacePatches
    ;
  kernelPatches = surfacePatches {
    version = pkgVersion;
    patchFn = ./kernel/${versions.majorMinor pkgVersion}/patches.nix;
    patchSrc = (repos.linux-surface + "/patches/${versions.majorMinor pkgVersion}");
  };
  kernelPackages = linuxPackage {
    inherit kernelPatches;
    version = srcVersion;
    sha256 = srcHash;
    ignoreConfigErrors = true;
  };

in
{
  options.hardware.microsoft-surface.kernelVersion = mkOption {
    description = "Kernel Version to use (patched for MS Surface)";
    type = types.enum [
      "longterm"
      "stable"
    ];
    default = "longterm";
  };

  config = {
    boot = {
      inherit kernelPackages;

      # Seems to be required to properly enable S0ix "Modern Standby":
      kernelParams = mkDefault [ "mem_sleep_default=deep" ];
    };

    # NOTE: Check the README before enabling TLP:
    services.tlp.enable = mkDefault false;

    # Needed for wifi firmware, see https://github.com/NixOS/nixos-hardware/issues/364
    hardware = {
      enableRedistributableFirmware = mkDefault true;
      sensor.iio.enable = mkDefault true;
    };
  };
}
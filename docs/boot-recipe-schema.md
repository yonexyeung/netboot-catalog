# Boot Recipe Schema v0.1

## Metadata

-   id
-   name
-   distribution
-   version
-   architecture
-   maintainer
-   schema_version
-   recipe_revision

## Detection

-   volume_label
-   file_exists
-   regex
-   metadata

## Assets

-   kernel
-   initrd\[\]
-   rootfs\[\]
-   modules\[\]
-   firmware\[\]

## Boot Parameters

Supports template variables.

## Validation

-   required_files
-   kernel_exists
-   initrd_exists
-   checksum

## Compatibility

-   BIOS
-   UEFI
-   HTTP
-   TFTP
-   iPXE
-   GRUB

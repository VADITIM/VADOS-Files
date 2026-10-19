# Known issues

- **A locked LUKS drive is not listed.** `PlacesModel::refreshDrives` skips `crypto_LUKS` partitions; it shows once unlocked (its mapper child has the filesystem). Listing it needs an unlock step (`udisksctl unlock`) with a passphrase prompt.

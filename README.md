# OCFL-Stanford
Gem to create OCFL inventories from Stanford Moab objects.

## Installation
Install the gem. That should also install the pre-req gems.

## Basic Usage
Configure your storage services as with Moab. To create an OCFL inventory
and sidecar digest file in the Druid's existing object directory, do:
```
require 'ocfl-stanford'

Moab::Config.configure do
  storage_roots ['/Users/jmorley/Documents/source3']
  storage_trunk 'sdr2objects'
  deposit_trunk 'deposit'
  # path_method 'druid_tree'  # druid_tree is the default path_method
end

druid='bj102hs9687'

# Given a [String] druid, make an OCFL inventory file in the object root.
OcflStanford::DruidExport.new(druid).make_inventory
```

## Advanced Usage
( Not really, it's not that complicated.)

To control where the inventory and digest files are created, do:
```
ocfl = OcflStanford::DruidExport.new(druid)
ocfl.export_directory = '/some/path/for/inventory'
ocfl.make_inventory
```
More fine-grained control can be had via `OcflStanford::MoabExport` and OcflTools:
```
export = StanfordTools::MoabExport.new(moab)

# We want to extract sha256 digests.
export.digest = 'sha256'

# OfclTools should have been installed by gem dependencies.
ocfl = OcflTools::OcflInventory.new

ocfl.id       = export.digital_object_id
ocfl.versions = export.generate_ocfl_versions
ocfl.manifest = export.generate_ocfl_manifest
ocfl.set_head_from_version(export.current_version_id)

# We'd also like to extract the md5 digests for additional fixity.
export.digest = 'md5'
ocfl.fixity = export.generate_ocfl_fixity

ocfl.to_file(path)
```

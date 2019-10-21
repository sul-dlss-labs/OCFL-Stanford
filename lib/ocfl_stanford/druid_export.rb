module OcflStanford
  class DruidExport
    # A convenience class that wraps MoabExport and OcflInventory to produce an OCFL inventory file.

    attr_accessor :export_directory

    attr_reader :path, :moab, :export

    def initialize(druid)
      # @param [String] druid, a Stanford Druid object ID.

      @path = Moab::StorageServices.object_path( druid )
      @moab = Moab::StorageObject.new( druid , @path )
      @export = OcflStanford::MoabExport.new(@moab)
      @export_directory = @moab.object_pathname # default value, can be changed.
    end

    def make_inventory
      @export.digest = 'sha256'
      ocfl = OcflTools::OcflInventory.new
      ocfl.id       = @export.digital_object_id
      ocfl.versions = @export.generate_ocfl_versions
      ocfl.manifest = @export.generate_ocfl_manifest
      ocfl.set_head_from_version(@export.current_version_id) # to set @head.

      # put versionMetadata in version description field, if it exists.
      my_messages = @export.generate_ocfl_messages
      my_messages.each do | version, message |
        ocfl.set_version_message(version, message)
      end

      @export.digest = 'md5'
      ocfl.fixity = @export.generate_ocfl_fixity

      ocfl.to_file(@export_directory)
    end
  end
end

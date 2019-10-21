module OcflStanford
  # A convenience class that wraps MoabExport and OcflInventory to produce an OCFL inventory file.
  class DruidExport

    # @return [Pathname] the directory to write the OCFL inventory.json file to.
    attr_accessor :export_directory

    # @return [Pathname] the Moab object root directory.
    attr_reader :path

    # @return [Moab::StorageObject] the Moab object on which we are performing work.
    attr_reader :moab

    # @return [OcflStanford::MoabExport] the OCFL Stanford object that will perform queries on the {moab} object.
    attr_reader :export

    # @param druid [String] a Stanford Druid object ID.
    def initialize(druid)

      @path = Moab::StorageServices.object_path( druid )
      @moab = Moab::StorageObject.new( druid , @path )
      @export = OcflStanford::MoabExport.new(@moab)
      @export_directory = @moab.object_pathname # default value, can be changed.
    end

    # Create an OCFL inventory object and write it to an export directory.
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

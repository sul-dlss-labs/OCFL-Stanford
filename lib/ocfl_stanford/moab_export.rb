module OcflStanford
  # Retrieves and queries Moab objects to make OCFL-friendly inputs.
  class MoabExport

    # @return [Array{Integer}] a series of integers representing all versions of the Moab object.
    attr_reader :versions

    # @return [String] the digital object ID (Stanford druid)
    attr_reader :digital_object_id

    # @return [Integer] the most recent version of the Moab (Stanford druid)
    attr_reader :current_version_id

    # @return [String] the algorithm used to compute hashes.
    attr_accessor :digest

    # @param moab {Moab::StorageObject} the Moab object on which to perform work.
    def initialize(moab)
      raise "This isn't a Moab object, n00b" unless moab.is_a?(Moab::StorageObject)

      @moab               = moab
      @versions           = @moab.version_id_list  # remember, versions must be Integers.
      @digital_object_id  = @moab.digital_object_id
      @current_version_id = @moab.current_version_id
      @digest             = 'md5' # default value, but can be changed to sha1 or sha256.

    end

      # used by get_deltas
      # @param [Integer] version of object to generate inventory for.
      # @return [Hash] of all files and checksums that represent the object at given version.
    def version_inventory(version)
      self.get_inventory('version', version)
    end

    # used by generate_ocfl_manifest_until_version
    # @param [Integer] version of object to generate inventory for.
    # @return [Hash] of all files and checksums that were added or modified at this version.
    def version_additions(version)
      self.get_inventory('additions', version)
    end

    # used by get_prior_delta
    # @param version [Integer] version of object to generate inventory file for.
    # @return [Moab::FileInventory] for given version.
    def get_FileInventory(version)
      moab_version = @moab.find_object_version(version)
      moab_version.file_inventory( 'version' )
    end

    # Trawls Moab object's root directory and returns all files discovered.
    # @return [Array] of all files found relative to Moab object root.
    def list_all_files
      results = Array.new
      Dir.chdir("#{@moab.object_pathname}")
      @versions.each do | version |
        version_name = OcflTools::Utils.version_int_to_string(version)
        # Files only, Dir.glob('path/**/*').select{ |e| File.file? e }
        Dir.glob("#{version_name}/data/**/*").select.each do |e|
          if File.file? e
              results << e
            end
          end
        end
        return results
    end

    # @return [Hash] of digests with [Array] of filenames as values.
    # The returned [Hash] is the Manifest block of an OCFL object.
    # This method creates the manifest by searching the object_root on disk
    # and computing new checksums for all files found. By design, it runs
    # against all versions of the Moab.
    def generate_ocfl_manifest_from_disk
      my_files = self.list_all_files # includes 'v0001/' prepending.
      my_manifest = Hash.new

      my_files.each do | file |
        full_filepath = "#{@moab.object_pathname}" + "/" + "#{file}"
        checksum = OcflTools::Utils.generate_file_digest(full_filepath, @digest)
        if my_manifest.has_key? checksum
          existing_entries = my_manifest[checksum]
          existing_entries.concat( [ file ] ) # NOT the FULL filepath; relative to object root.
          # Make unique.
          unique_entries = existing_entries.uniq
          my_manifest[checksum] = unique_entries
        end
        # if the checksum isn't already there, add it as a new key. File must be in an array.
        my_manifest[checksum] = [ file ]
      end
      return my_manifest
    end

    # queries Moab workflow metadata object for description information.
    # @return [Hash] of version [Integer] and descriptions.
    def generate_ocfl_messages
      vm = Moab::StorageServices.version_metadata(@digital_object_id)
      vm2 = Moab::VersionMetadata.read_xml_file(vm.dirname, vm.basename)
      my_messages = Hash.new
      vm2.versions.each do | md |
        my_messages[md.version_id] = md.description
      end
      return my_messages
    end

    def generate_ocfl_message(version)
    end

    # @return [Hash] of fixity information for the complete Moab object, suitable
    # for providing to the fixity block of an OCFL object.
    def generate_ocfl_fixity
      self.generate_ocfl_fixity_until_version(@current_version_id)
    end

    # Fixity is basically a Manifest block inside a wrapping hash.
    # @param version [Integer] version number to generate manifest for. Manifest will include all prior versions.
    # @return [Hash] of fixity digest/filename pairs for provided version.
    def generate_ocfl_fixity_until_version(version)
      my_fixity = Hash.new
      my_fixity["#{@digest}"] = generate_ocfl_manifest_until_version(version)
      return my_fixity
    end

    # Generates an OCFL-compliant manifest block for the Moab at current version.
    # @return [Hash] OCFL-compliant Manifest block; keys are digests, values are [Array] of files.
    def generate_ocfl_manifest
      self.generate_ocfl_manifest_until_version(@current_version_id)
    end

    # Produces a partial manifest; i.e. if the Moab has a current version of 9,
    # this method can produce a manifest up to version 7. Used for back-filling Moab version directories
    # with valid OCFL inventories, and for creating OCFL Manifests by inspecting Moab Manifests
    # rather than discovering files on disk and re-generating checksums.
    # @param version [Integer] version number to generate manifest for. Manifest will include all prior versions.
    # @return [Hash] OCFL-compliant Manifest block; keys are digests, values are [Array] of files.
    def generate_ocfl_manifest_until_version(version)
      my_version = 0
      my_manifest = Hash.new

      while my_version < version
        my_version = my_version + 1
        my_version_name = OcflTools::Utils.version_int_to_string(my_version)  # [String] 'v0001' etc
        my_files_and_checksums = self.version_additions(my_version)

        my_files_and_checksums.each do | file, checksums |
          # Checksums is an [Array], but should only have 1 value in it.
          checksum = checksums[0]
          # We also need to append version_name to file.
          filepath = "#{my_version_name}/data/#{file}"
          # We need to flip the results around so checksum becomes the key, [Array] filepath is value.
          if my_manifest.has_key? checksum
            existing_entries = my_manifest[checksum]
            existing_entries.concat( [ filepath ] ) # NOT the FULL filepath; relative to object root.
            # Make unique.
            unique_entries = existing_entries.uniq
            my_manifest[checksum] = unique_entries
          end
          # If the checksum isn't already there, add it as a new key. File must be in an array.
          my_manifest[checksum] = [ filepath ]
        end
      end
      return my_manifest
    end

    # @param version [Integer] version to create state block for.
    # @return [Hash] OCFL-compliant state block, used in OCFL Versions block.
    def generate_ocfl_state(version)
      input = self.version_inventory(version)
      # input is a [Hash] with files as key, digests as checksum.
      # It needs to be flipped around to checksums as key, files as values in arrays.
      my_state = Hash.new

      input.each do | file, checksums |
        # Checksums is an [Array], but should only have 1 value in it.
        checksum = checksums[0]
        if my_state.has_key? checksum
          existing_entries = my_state[checksum]
          existing_entries.concat( [ file ] ) # NOT the FULL filepath; relative to object root.
          # Make unique.
          unique_entries = existing_entries.uniq
          my_state[checksum] = unique_entries
        end
        # If the checksum isn't already there, add it as a new key. File must be in an array.
        my_state[checksum] = [ file ]
      end
      return my_state
    end

    # Calls {#generate_ocfl_state} for each version
    # @return [Hash] of versions in OCFL format.
    def generate_ocfl_versions
      my_versions = Hash.new
      @versions.each do | version |
        this_version = Hash.new #
        version_name = OcflTools::Utils.version_int_to_string(version) # 'v0001' etc.

        this_version['created'] = 'A placeholder value'
        this_version['message'] = 'Placeholder text goes here'

        my_user = Hash.new
        my_user['name'] = 'John Hancock'
        my_user['address'] = 'jhancock@congress.org'

        this_version['user'] = my_user

        this_version['state'] = self.generate_ocfl_state(version)

        my_versions[version_name] = this_version
      end
      return my_versions
    end

    # Convenience method for CLI and debugging.
    # @return Puts all deltas of this object to std out.
    def print_deltas
      self.get_deltas.each do | version, delta |
        puts "#{@digital_object_id},#{version}"
        delta.each do | action, result|
          puts "  #{action}:"
          result.each do | filestream |
            filestream.each do | filename, checksums |
              if checksums.length > 1
                # Highest value in checksums array is most recent.
              puts "    #{filename} new #{self.digest}: #{checksums[1]} previous #{self.digest}: #{checksums[0]}"
                else
              puts "    #{filename} new #{self.digest}: #{checksums[0]}"
              end
            end
          end
        end
      end
    end

    # A summary method that returns all changes for all versions of this object in a nested hash.
    # @return [Hash] of changes for all versions.
    def get_deltas
      my_versions = Hash.new

      # version 1 is a special case because it a) always exists and b) has no prior version to compare to.
      v1 = Hash.new
      added = self.version_inventory(1) # Hash of first version is all additions.

      # self.version_inventory returns a Hash of files and checksums.
      # It needs re-formatting to align with the results of Moab::FileInventoryDifference.
      my_array = []
      added.each do | k,v |
          my_hash = {}
          my_hash[k] = v
          my_array << my_hash # Creates an Array of single key/value Hashes.
      end

      # The change key 'added' needs to contain values as an array, to match format of other versions
      v1["added"] = my_array # and again, all actions in version 1 are additions.

      # Add the version 1 hash to our final Hash'o'hashes report out.
      my_versions[1] = v1

      # We are assuming the Moab is well-formed, so length == 1 == only 1 version in the Moab.
      if @versions.length == 1
        return my_versions
      end
      # otherwise, do versions > 1.
      version = 1
      while version < @versions.length
        version = version + 1
        my_versions[version] = self.get_prior_delta(version)
      end
      return my_versions
    end

    # Generates the changes between the requested version and the version immediately prior.
    # @param version [Integer] version of object to generate delta for.
    # @return [Hash] of actions that have been performed on this Moab since the prior version.
    def get_prior_delta(version)

      raise "Provided version must be greater than 1!" unless version > 1

      prior_version = version - 1

      current_version_inventory = self.get_FileInventory(version)
      prior_version_inventory   = self.get_FileInventory(prior_version)

      inventory_diff = Moab::FileInventoryDifference.new
      inventory_diff.compare(prior_version_inventory, current_version_inventory)

      my_results = Hash.new
      my_results = inventory_diff.differences_detail # returns a [Hash] of results

      combined_results = Hash.new # The Hash we'll use to report out.

      my_results["group_differences"].each do | group |
        # Group is an [Array] of arrays, one array per group.
        # each group array consists of two elements: group_id and a [Hash] of content.
        # Everything we need is in the second element (the Hash).
        if group[1]["difference_count"] == 0
          next # If there are no differences in this group between versions, skip it.
        end

        my_group = group[1]["group_id"] # Get this for later. It'll be 'metadata' or 'content'

        group[1]["subsets"].each do |  subset |
          # A subset value is 'added' 'modified' 'deleted' or 'renamed'(?)
          # A subset is an Array containing 2 elements; 1 [String] (name) and 1 [Hash].
          # As before, everything we need is in the [Hash] in the 2nd element.

          change = "#{subset[1]["change"]}" # capture the type of change for later.

          subset[1]["files"].each do | file |
            # This is also an Array of 2 elements. First element is a [Integer].
            # 2nd element is a [Hash] of useful data.

            # 'modified' has filename in basis_path, 'same' in other_path, 2 checksums.
            # 'added' has null in basis_path, filename in other_path, 1 checksum.
            # presumably renames have value in both; we just want the NEW name (we can work out the old one from checksums)

            file_path = "#{my_group}/#{file[1]["other_path"]}"
            file_path = "#{my_group}/#{file[1]["basis_path"]}" unless file[1]["basis_path"] == ''

            my_checksums = []
            file[1]["signatures"].each do | signature |
              # Modified has 2 signatures. Adds have 1. We need to capture these in an array.
              # Each signature block has 3 different digests. Pick one (md5, sha1, sha256).
              my_checksums << signature[1][@digest]
            end
            # Now make a [Hash] of our results for this file, a single key with an Array of checksums.
            my_file_and_sums = { "#{file_path}" => my_checksums }

            # create the key (with the type of change) with an empty [Array] as value if it doesn't already exist.
            combined_results["#{change}"] = [] unless combined_results.has_key? "#{change}"

            # Now get that [Array] and append my_file_and_sums to it.
            add_me = combined_results["#{change}"]  # Get the existing [Array] out of the [Hash]
            add_me << my_file_and_sums              # Add our new [Hash] to the [Array].
            combined_results["#{change}"] = add_me  # and put the expanded [Array] back into combined_results.
          end
        end
      end
      return combined_results
    end

    # Gets the Moab inventory for the requested inventory type and version.
    # @param inventory [String] is one of 'additions', 'manifests', 'version'.
    # @param version [Integer] version of Moab to get inventory for.
    # @return [Hash] of files and checksums for given inventory type and version.
    def get_inventory(inventory, version)

      moab_version = @moab.find_object_version( version )

      file_inventory = moab_version.file_inventory( inventory ) # String is one of : additions, manifests, version

      my_files = Hash.new # Our Hash return value.

      file_inventory.groups.each do | group |
        group.files.each do | file |
          file.instances.each do | instance |
            #           Moab::StorageServices.retrieve_file(file_category, file_id, object_id, version_id = nil)
            file_path = Moab::StorageServices.retrieve_file( "#{group.group_id}", "#{instance.path}", @moab.digital_object_id , version )
            case @digest
              when 'md5'
                checksum = file.signature.md5
              when 'sha1'
                checksum = file.signature.sha1
              when 'sha256'
                checksum = file.signature.sha256
              else
                raise "Unknown digest type!"
            end
             # And checksum needs to be in an array.
             my_checksums = []
             my_checksums << checksum
             my_files["#{group.group_id}/#{instance.path}"] = my_checksums
          end
        end
      end
      return my_files
    end

  end
end

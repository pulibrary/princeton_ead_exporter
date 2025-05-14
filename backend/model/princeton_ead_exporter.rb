require 'nokogiri'
require 'securerandom'

class EADSerializer < ASpaceExport::Serializer
  serializer_for :ead

  def serialize_container(inst, xml, fragments)
    atts = {}

    sub = inst['sub_container']
    top = sub['top_container']['_resolved']

    atts[:id] = prefix_id(SecureRandom.hex)
    last_id = atts[:id]

    atts[:type] = top['type']
    text = top['indicator']

    atts[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}",
                          :default => inst['instance_type'])
    atts[:label] << " [#{top['barcode']}]" if top['barcode']

    # Add location code to the altrender attribute.
    if(collection = top["collection"])
      if(collection && collection.first)
        collection_identifier = collection.first["identifier"]
        if (location_code = top["long_display_string"].match(/\[([^\[\]]*)\], #{collection_identifier}/))
          atts[:altrender] = location_code[1]
        end
      end
    end
    if (cp = top['container_profile'])
      atts[:encodinganalog] = cp['_resolved']['url'] || cp['_resolved']['name']
    end
    if(cl = top['container_locations'])
      cl = (cl || []).first || {}
      note = cl["note"]
      if(cl["note"])
        atts[:note] = cl["note"]
      end
    end

    xml.container(atts) {
      sanitize_mixed_content(text, xml, fragments)
    }

    (2..3).each do |n|
      atts = {}

      next unless sub["type_#{n}"]

      atts[:id] = prefix_id(SecureRandom.hex)
      atts[:parent] = last_id
      last_id = atts[:id]

      atts[:type] = sub["type_#{n}"]
      text = sub["indicator_#{n}"]

      xml.container(atts) {
        sanitize_mixed_content(text, xml, fragments)
      }
    end
  end

  # Serializes the the JSONModel notes into XML Elements for the EAD Document
  # @param note [Hash]
  # @param xml [Nokogiri::XML::Builder]
  # @param fragments [RawXMLHandler]
  # @param sort_names [Array<String>]
  # @note Princeton Modifications: sort_names is used to construct the XML elements containing the personal names
  def serialize_note_content(note, xml, fragments, sort_names = [])
    return if note["publish"] === false && !@include_unpublished
    audatt = note["publish"] === false ? {:audience => 'internal'} : {}
    content = note["content"]

    atts = {:id => prefix_id(note['persistent_id']) }.reject{|k,v| v.nil? || v.empty? || v == "null" }.merge(audatt)
    # Begin Princeton Modifications
    # Add rights restriction to accessrestrict notes.
    if note["rights_restriction"] && note["rights_restriction"]["local_access_restriction_type"]
      rights_restriction = note["rights_restriction"]["local_access_restriction_type"].first
      atts["rights-restriction"] = rights_restriction if rights_restriction
    end
    # End Princeton Modifications

    head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
    content, head_text = extract_head_text(content, head_text)

    xml.send(note['type'], atts) {
      # Begin Princeton Modifications
      sort_names.each do |sort_name|
        xml.note(label: 'personal-name') { xml.text(sort_name) }
      end
      # End Princeton Modifications

      xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content )

      sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content

      if note['subnotes']
        serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
      end
    }
  end

  # Serializes the the JSONModel notes for linked Agents into XML snippets for the EAD Document
  # @param data
  # @param xml [Nokogiri::XML::Builder]
  # @param fragments [RawXMLHandler]
  # @note Princeton Modifications: sort_names is extracted from the agent['names'] and used to construct the XML elements containing the personal names
  def serialize_agent_notes(data, xml, fragments)
    unless data.creators_and_sources.nil?
      data.creators_and_sources.each do |link|

        agent = link['_resolved']
        published = agent['publish'] === true

        next if !published && !@include_unpublished
        sort_name_values = agent['names'].select { |x| x.key?('sort_name') }
        sort_names = sort_name_values.map { |v| v['sort_name'] }

        notes = agent['notes'].select { |x| x['jsonmodel_type'] == "note_bioghist" }

        notes.each do |note|
          note['type'] = 'bioghist'
          note['internal'] = false
          note['publish'] = true

          serialize_note_content(note, xml, fragments, sort_names)
        end
      end
    end
  end

  def serialize_nondid_notes(data, xml, fragments)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next if note['internal']
      next if note['type'].nil?
      next unless data.archdesc_note_types.include?(note['type'])
      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      if note['type'] == 'legalstatus'
        xml.accessrestrict(audatt) {
          serialize_note_content(note, xml, fragments)
        }
      else
        serialize_note_content(note, xml, fragments)
      end
    end
    serialize_agent_notes(data, xml, fragments)
  end

  # Patch handle_linebreaks to deal with mixed content in <p> tags.
  # @todo Remove when fixed upstream.
  def handle_linebreaks(content)
    # 4archon...
    content.gsub!("\n\t", "\n\n")
    # PRINCETON PATCH
    # Replace <p> with two linebreaks to ensure that content in each section is
    # properly escaped for output.
    content.gsub!("</p>", "\n\n")
    content.gsub!("<p>", "")
    # END PRINCETON PATCH (some code below is dead now, but left for the sake of
    # similarity)
    # if there's already p tags, just leave as is
    return content if ( content.strip =~ /^<p(\s|\/|>)/ or content.strip.length < 1 )
    original_content = content
    blocks = content.split("\n\n").select { |b| !b.strip.empty? }
    if blocks.length > 1
      content = blocks.inject("") do |c,n|
        c << "<p>#{escape_content(n.chomp)}</p>"
      end
    else
      content = "<p>#{escape_content(content.strip)}</p>"
    end

    # just return the original content if there's still problems
    xml_errors(content).any? ? original_content : content
  end
end

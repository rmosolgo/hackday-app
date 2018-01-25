class Command
  # The commit message
  attr_reader :message

  def initialize(comment)
    @body = comment["body"]
    comment_hunk = comment["diff_hunk"]
    # Position _in_ the hunk:
    position = comment["position"]
    # original start, original lines, new start, new lines
    match = comment_hunk.match(/@@ -(?<os>\d+),(?<ol>\d+) \+(?<ns>\d+),(?<nl>\d+) @@/)
    # "position" is 1-indexed, so subtract the one
    @line = match[:os].to_i + (position - 1)
    @file = comment["path"]

    first_line = comment_body.split("\n").first
    command_text = first_line.sub(/^simon says /, "")
    case command_text
    when /remove file/
      @message = "Remove #{@file}"
      @type = :remove_file
    when /delete line/
      @message = "Delete line #{@line} of #{@file}"
      @type = :delete_line
    when /insert line/
      @message = "Insert blank line after line #{@line} of #{@file}"
      @type = :insert_line
    else
      raise "Unknown command text: #{command_text}"
    end
  end

  # Returns a new tree
  def perform(tree, client)
    new_tree = tree.map do |entry|
      if entry["path"] == @file
        file_content = client.get_blob_content(entry["sha"])
        new_entry = {
          "path" => entry["path"],
          "mode" => entry["mode"],
          "type" => entry["type"],
        }

        case @type
        when :remove_file
          nil
        when :delete_line
          lines = file_content.split("\n")
          line_idx = @line - 1
          lines.delete(line_idx)
          new_entry["content"] = lines.join("\n")
          new_entry
        when :insert_line
          lines = file_content.split("\n")
          line_idx = @line - 1
          lines.insert(line_idx, "")
          new_entry["content"] = lines.join("\n")
        else
          raise "Not implemented type: #{@type}"
        end
      else
        entry
      end
    end
    # Remove deleted
    new_tree.compact
  end
end

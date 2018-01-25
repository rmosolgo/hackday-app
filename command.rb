class Command
  # The commit message
  attr_reader :message

  def initialize(comment)
    log("comment keys: #{comment.keys}")
    @body = comment["body"]
    comment_hunk = comment["diff_hunk"]
    log("hunk: #{comment_hunk}")
    # Position _in_ the hunk:
    position = comment["position"]
    # original start, original lines, new start, new lines
    match = comment_hunk.match(/@@ -(?<os>\d+),(?<ol>\d+) \+(?<ns>\d+),?(?<nl>\d+)? @@/)
    log("match: #{match}")
    @line = match[:ns].to_i + (position - 1)
    @file = comment["path"]
    log("commented on: #{@line} of #{@file}")

    first_line = @body.split("\n").first
    command_text = first_line.sub(/^simon says /, "")
    case command_text
    when /capitalize /
      _cap, term = command_text.split(" ")
      @sub_find = term
      @sub_replace = term.capitalize
      @type = :sub
      @message = "Capitalize \"#{@sub_replace}\" on line #{@line} of #{@file}"
    when /sub /
      _sub, from, to = command_text.split(" ")
      @sub_find = from
      @sub_replace = to
      @type = :sub
      @message "Replace \"#{@sub_find}\" with \"#{@sub_replace}\" in line #{@line} of #{@file}"
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
    log("Message: #{@message}")
  end

  # Returns a new tree
  def perform(tree, client)
    new_tree = tree.map do |entry|
      if entry["path"] == @file
        file_content = client.get_blob_content(entry["sha"])
        lines = file_content.split("\n")
        line_idx = @line - 1
        suffix = file_content.end_with?("\n") ? "\n" : ""
        new_entry = {
          "path" => entry["path"],
          "mode" => entry["mode"],
          "type" => entry["type"],
        }

        rebuilt_entry = case @type
        when :sub
          lines[line_idx] = lines[line_idx].gsub(@sub_find, @sub_replace)
        when :remove_file
          nil
        when :delete_line
          lines.delete_at(line_idx)
          new_entry["content"] = lines.join("\n") + suffix
          new_entry
        when :insert_line
          lines.insert(line_idx + 1, "")
          new_entry["content"] = lines.join("\n") + suffix
          new_entry
        else
          raise "Not implemented type: #{@type}"
        end

        log("Rebuilt by #{@type}: #{rebuilt_entry}")

        rebuilt_entry
      else
        entry
      end
    end
    # Remove deleted
    t = new_tree.compact
    log("New tree: #{t}")
    t
  end

  private

  def log(msg)
    puts "[CLIENT] #{msg}"
  end
end

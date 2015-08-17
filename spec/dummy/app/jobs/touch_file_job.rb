class TouchFileJob < Struct.new(:file)
  def perform
    Rails.logger.info("Touching #{file}")
    FileUtils.makedirs(File.dirname(file))
    FileUtils.touch(file)
  end
end

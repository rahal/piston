require "test/unit"
require "rubygems"
require "pathname"
require "logger"
require "mocha"

$:.unshift File.dirname(__FILE__) + '/../lib'
$:.unshift File.dirname(__FILE__) + '/../../piston-core/lib'

require "piston_core"
require "piston_git"
require "piston_git/repository"
require "piston_git/commit"
require "piston_git/working_copy"

PISTON_DEFAULT_LOGGER = Logger.new("log/test.log")
PistonCore::Repository.logger = PistonCore::WorkingCopy.logger = PISTON_DEFAULT_LOGGER

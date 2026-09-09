package.path = package.path .. ";./?.lua"
require("tests.bytes_spec")
require("tests.transport.mspChunk_spec")
require("tests.transport.msp_spec")
require("tests.transport.mspBuffer_spec")
require("tests.mspMsgs_spec")
require("tests.state_spec")
require("tests.safety_spec")

local testkit = require("tests.testkit")
local _, failCount = testkit.run()
os.exit(failCount > 0 and 1 or 0)

local classic = require 'classic'
local Model = require 'Model'

local AsyncModel = classic.class('AsyncModel')

function AsyncModel:_init(opt)
  -- Initialise Catch or Arcade Learning Environment
  log.info('Setting up ' .. (opt.ale and 'Arcade Learning Environment' or 'Catch'))
  local Env = opt.ale and require 'rlenvs.Atari' or require 'rlenvs.Catch'
  self.env = Env(opt)
  local stateSpec = self.env:getStateSpec()

  -- Provide original channels, height and width for resizing from
  opt.origChannels, opt.origHeight, opt.origWidth = table.unpack(stateSpec[2])
  -- Extra safety check for Catch
  if not opt.ale then -- TODO: Remove eventually
    opt.height, opt.width = stateSpec[2][2], stateSpec[2][3]
  end
  -- Set up fake training mode (if needed)
  if not self.env.training then
    self.env.training = function() end
  end
  -- Set up fake evaluation mode (if needed)
  if not self.env.evaluate then
    self.env.evaluate = function() end
  end

  self.model = Model(opt)
  self.a3c = opt.async == 'A3C'

  classic.strict(self)
end

function AsyncModel:getEnvAndModel()
  return self.env, self.model
end

function AsyncModel:createNet()
  local actionSpec = self.env:getActionSpec()
  local m = actionSpec[3][2] - actionSpec[3][1] + 1 -- Number of discrete actions
  return self.model:create(m)
end


return AsyncModel
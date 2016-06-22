local classic = require 'classic'
local optim = require 'optim'
local QAgent = require 'async/OneStepQAgent'
require 'modules/sharedRmsProp'

local EpisodicOneStepQAgent, super = classic.class('EpisodicOneStepQAgent', 'OneStepQAgent')


function EpisodicOneStepQAgent:_init(opt, policyNet, targetNet, theta, targetTheta, atomic, sharedG)
  self.eta = opt.mcEta
  self.rewards = {}
  self.actions = {}
  self.states = {}
  self.Qs = {}
  super._init(self, opt, policyNet, targetNet, theta, targetTheta, atomic, sharedG)
  self.agentName = 'EpisodicOneStepQAgent'
end


function EpisodicOneStepQAgent:learn(steps, from)
  self.step = from or 0
  self.policyNet:training()
  self.stateBuffer:clear()
  self.env:training()

  log.info('%s starting | steps=%d | ε=%.2f -> %.2f', self.agentName, steps, self.epsilon, self.epsilonEnd)
  local reward, terminal, state = self:start()

  local action, state_

  self.batchIdx = 1
  self.states[self.batchIdx] = state:clone()

  self.tic = torch.tic()
  for step1=1,steps do
    if not terminal then
      action = self:eGreedy(state, self.policyNet)
      reward, terminal, state_ = self:takeAction(action)
    else
      reward, terminal, state_ = self:start()
    end

    self.batchIdx = self.batchIdx + 1

    self.states[self.batchIdx] = state_:clone()
    self.actions[self.batchIdx] = action
    self.rewards[self.batchIdx] = reward
    self.Qs[self.batchIdx] = self.QCurr:clone()

    if not terminal then
      state = state_
    else
      self:learnEpisode(steps)
      state = nil
      self.batchIdx = 0
      self.actions = {}
      self.rewards = {}
      self.states = {}
      self.Qs = {}
    end
  end

  log.info('%s ended learning steps=%d ε=%.4f', self.agentName, steps, self.epsilon)
end


function EpisodicOneStepQAgent:learnEpisode(steps)
--  log.info('learning episode length=%d', #self.rewards)
local suc = self.rewards[self.batchIdx]  > 0

  for i=2,#self.rewards do
    local terminal = i == self.batchIdx
    local state = self.states[i-1]
    local state_ = self.states[i]
    local action = self.actions[i]
    local reward = self.rewards[i]

    local tdErrQ = self:computeTdErrQ(state, action, state_, reward, terminal)

    local totalReward = 0
    local gamma = 1
    if self.eta < 1 then
      for r=i,#self.rewards do
        totalReward = gamma * self.rewards[r]
        gamma = gamma * self.gamma
        if gamma < 0.001 then break end
      end
    end
    local mcReturn = totalReward - self.Qs[i][action]

    local mixedDelta = self.eta * tdErrQ + (1- self.eta) * mcReturn

if suc then
--    log.info('tdQ %f + mc %f = %f r=%f R=%f', tdErrQ, mcReturn, mixedDelta, self.rewards[i], totalReward)
end
    self:accumulateGradientTdErr(state, action, mixedDelta, self.policyNet)

    if i % self.batchSize == 0 or terminal then

      self:applyGradients(self.policyNet, self.dTheta, self.theta)
    end
    self:progress(steps)
  end
end


return EpisodicOneStepQAgent

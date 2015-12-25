local experience = {}

-- Creates experience replay memory
experience.create = function(opt)
  local memory = {}
  local stateSizes = torch.LongStorage({opt.memSize, opt.nChannels, opt.height, opt.width}) -- Calculate state/transition storage size
  -- Allocate memory for experience
  memory.states = torch.Tensor(stateSizes)
  memory.actions = torch.Tensor(opt.memSize)
  memory.rewards = torch.Tensor(opt.memSize)
  memory.transitions = torch.Tensor(stateSizes)
  memory.terminals = torch.ByteTensor(opt.memSize) -- Terminal conditions stored as 0 = false, 1 = true
  -- Internal pointer
  memory.nextIndex = 1
  memory.isFull = false
  -- TD-error δ-based priorities
  memory.priorities = torch.Tensor(opt.memSize)
  local smallConst = 1e-9
  memory.maxPriority = opt.tdClamp -- Should prioritise sampling experience that has not been learnt from

  -- Returns number of saved tuples
  memory.size = function(self)
    return self.isFull and opt.memSize or self.nextIndex - 1
  end

  -- Store new experience tuple
  memory.store = function(self, state, action, reward, transition, terminal)
    self.states[{{self.nextIndex}, {}}] = state:float()
    self.actions[self.nextIndex] = action
    self.rewards[self.nextIndex] = reward
    self.transitions[{{self.nextIndex}, {}}] = transition:float()
    self.terminals[self.nextIndex] = terminal and 1 or 0
    -- Store with maximal priority
    self.priorities[self.nextIndex] = self.maxPriority + smallConst
    self.maxPriority = self.maxPriority + smallConst

    -- Increment index
    self.nextIndex = self.nextIndex + 1
    -- Circle back to beginning if memory limit reached
    if self.nextIndex > opt.memSize then
      self.isFull = true -- Full memory flag
      self.nextIndex = 1 -- Reset nextIndex
    end
  end

  -- Retrieve experience tuples
  memory.retrieve = function(self, indices)
    local s, a, r, tr, te = self.states:index(1, indices), self.actions:index(1, indices), self.rewards:index(1, indices), self.transitions:index(1, indices), self.terminals:index(1, indices)
    if opt.gpu > 0 then
      return s:cuda(), a, r:cuda(), tr:cuda(), te
    else
      return s, a, r, tr, te
    end
  end

  -- Update experience priorities
  memory.updatePriorities = function(self, indices, priorities)
    for p = 1, indices:size(1) do
      self.priorities[indices[p]] = priorities[p] + smallConst -- Allows transitions to be sampled even if error is 0
    end
  end

  -- Retrieve experience priorities
  memory.retrievePriorities = function(self, indices)
    return self.priorities:index(1, indices)
  end

  -- Converts a CDF from a PDF
  local pdfToCdf = function(pdf)
    local c = 0
    pdf:apply(function(x)
      c = c + x
      return c
    end)
  end

  -- Returns indices and importance-sampling weights based on (stochastic) proportional prioritised sampling
  memory.prioritySample = function(self, priorityType)
    local N = self:size()
    local indices, w

    -- Priority 'none' = uniform sampling
    if priorityType == 'none' then
      indices = torch.randperm(N):long()
      indices = indices[{{1, opt.batchSize}}]
      w = torch.ones(opt.batchSize) -- Set weights to 1 as no correction needed
      
      return indices, w
    else
      -- Calculate sampling probability distribution P
      local expPriorities = torch.pow(self.priorities[{{1, N}}], opt.alpha) -- Use prioritised experience replay exponent α
      local Z = torch.sum(expPriorities) -- Normalisation constant
      local P = expPriorities:div(Z)

      -- Calculate importance-sampling weights w
      w = torch.pow(torch.mul(P, N), -opt.beta[opt.step]) -- Use importance-sampling exponent β
      w:div(torch.max(w)) -- Normalise weights so updates only scale downwards (for stability)

      -- Create a cumulative distribution for inverse transform sampling
      pdfToCdf(P) -- Convert distribution
      indices = torch.sort(torch.Tensor(opt.batchSize):uniform()) -- Generate uniform numbers for sampling
      -- Perform linear search to sample
      local minIndex = 1
      for i = 1, opt.batchSize do
        while indices[i] > P[minIndex] do
          minIndex = minIndex + 1
        end
        indices[i] = minIndex -- Get sampled index
      end
      indices = indices:long() -- Convert to LongTensor for indexing

      return indices, w:index(1, indices)
    end
  end

  return memory
end

return experience
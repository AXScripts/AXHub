local ScriptEnv = ...

local Settings, Connections = ScriptEnv.Settings, ScriptEnv.Connections

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Stepped = RunService.Stepped
local Player = Players.LocalPlayer

local Characters = workspace.Characters
local Enemies = workspace.Enemies

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CommF, CommE = Remotes.CommF_, Remotes.CommE
local Net = Modules.Net

local _ENV = (getgenv or getrenv or getfenv)()

local BRING_TAG: string = _ENV._Bring_Tag or `b{math.random(80, 2e4)}t`
local KILLAURA_TAG: string = _ENV._KillAura_Tag or `k{math.random(120, 2e4)}t`

_ENV._Bring_Tag = BRING_TAG
_ENV._KillAura_Tag = KILLAURA_TAG

local function CreateNewClear()
  local COUNT_NEWINDEX = 0
  
  return {
    __newindex = function(self, index, value)
      if COUNT_NEWINDEX >= 50 then
        for key, cache in pairs(self) do
          if typeof(cache) == "Instance" and not cache:IsDescendantOf(game) then
            rawset(self, key, nil)
          end
        end
        COUNT_NEWINDEX = 0
      end
      
      COUNT_NEWINDEX += 1
      return rawset(self, index, value)
    end
  }
end

local function CreateDictionary(array: { string }, key: any?): { [string]: any }
  local Dictionary = {}
  
  for _, string in ipairs(array) do
    Dictionary[string] = if type(key) == "table" then {} else key
  end
  
  return Dictionary
end

local Module = {}

local Cached = {
  Humanoids = CreateNewClear(),
  Closest = nil
}

Module.GameData = {
  CurrentSea = ({ [2753915549] = 1, [4442272183] = 2, [7449423635] = 3 })[game.PlaceId] or 0,
  SeasName = { "Main", "Dressrosa", "Zou" },
  MaxMastery = 600,
  MaxLevel = 2600
}

function Module.IsAlive(Character: Model): boolean?
  local Humanoid = Character and (Cached.Humanoids[Character] or Character:FindFirstChildOfClass("Humanoid"))
  
  if Humanoid then
    if not Cached.Humanoids[Character] then
      Cached.Humanoids[Character] = Humanoid
    end
    
    return Humanoid.Health > 0
  end
end

function Module.EnemySpawned(EnemyName)
  if (tick() - Module.Debounce.GetEnemy) <= 0.25 then
    return nil
  end
  
  local Enemies = Module.Enemies
  local Enemy = if type(EnemyName) == "table" then Enemies:GetClosest(EnemyName) else Enemies:GetEnemyByTag(EnemyName)
  
  if Enemy then
    return Enemy
  elseif Settings.SmoothMode then
    Module.Debounce.GetEnemy = tick()
  end
end

function Module.EquipTool(ToolName: string, ByType: boolean?): (nil)
  ByType = if not ToolName then true else ByType
  ToolName = ToolName or Settings.FarmTool
  
  if not Module.IsAlive(Player.Character) then
    return nil
  end
  
  local Equipped = Cached.Equipped
  
  if Equipped and Equipped.Parent and Equipped[if ByType then "ToolTip" else "Name"] == ToolName then
    if Equipped:GetAttribute("Locks") then
      Equipped:SetAttribute("Locks", nil)
    end
    
    if Equipped.Parent == Player.Backpack then
      Player.Character.Humanoid:EquipTool(Equipped)
    elseif Equipped.Parent == Player.Character then
      return nil
    end
  end
  
  if ToolName and not ByType then
    local BackpackTool = Player.Backpack:FindFirstChild(ToolName)
    
    if BackpackTool then
      Cached.Equipped = BackpackTool
      Player.Character.Humanoid:EquipTool(BackpackTool)
    end
  else
    for _, Tool in Player.Backpack:GetChildren() do
      if Tool:IsA("Tool") and Tool.ToolTip == ToolName then
        Cached.Equipped = Tool
        Player.Character.Humanoid:EquipTool(Tool)
        return nil
      end
    end
  end
end

function Module:TravelTo(Sea: number?): (nil)
  return self.Network:InvokeServer(`Travel{self.GameData.SeasName[Sea]}`)
end

Module.UtilsModules = (function()
  local UtilsModules = {}
  
  UtilsModules.TweenCreator = function()
    local module = {}
    module.__index = module
    
    local TweenService = game:GetService("TweenService")
    
    local tweens = {}
    local EasingStyle = Enum.EasingStyle.Linear
    
    function module.new(obj, time, prop, value)
      local self = setmetatable({}, module)
      
      self.tween = TweenService:Create(obj, TweenInfo.new(time, EasingStyle), { [prop] = value })
      self.tween:Play()
      self.value = value
      self.object = obj
      
      if tweens[obj] then
        tweens[obj]:destroy()
      end
      
      tweens[obj] = self
      return self
    end
    
    function module:destroy()
      self.tween:Pause()
      self.tween:Destroy()
      
      tweens[self.object] = nil
      setmetatable(self, nil)
    end
    
    function module:stop(obj)
      if tweens[obj] then
        tweens[obj]:destroy()
      end
    end
    
    return module
  end
  
  UtilsModules.FarmQueue = function(Options)
    local Success, ErrorMessage = pcall(function()
      while task.wait() do
        local Enabled = false
        
        for _, Option in Options do
          Settings.RunningOption = Option.Name
          local Method = Option.Function()
          
          if Method then
            Settings.RunningMethod = type(Method) == "string" and Method
            Enabled = true; break
          else
            Settings.RunningOption, Settings.RunningMethod = nil, nil
          end
        end
        
        _ENV.OnFarm = (_ENV.teleporting or Enabled)
      end
    end)
    
    -- Module.Signals.Error:Fire(ErrorMessage)
  end
  
  UtilsModules.OptionsPlugin = function(EnabledOptions)
    local Plugin = {}
    
    function Plugin:Toggle(Config, Callback)
      if type(Callback) == "string" then
        local Flag = Callback
        
        Callback = function(Value)
          EnabledOptions[Flag] = Value
        end
      end
      
      local Title = Config[1] or Config.Title
      local Description = type(Config[2] or Config[3]) == "string" and (Config[2] or Config[3]) or ""
      local Default = type(Config[2] or Config[3]) == "boolean" and (Config[2] or Config[3]) or false
      
      local Toggle = self:AddToggle(Title, Description, Default)
      
      Toggle.OnToggle:Connect(Callback)
      
      return Toggle
    end
    
    return Plugin
  end
  
  return UtilsModules
end)()

Module.Network = (function()
  local Network = {}
  
  function Network:RemoteFunction(Name: string): RemoteFunction
    return Net["RF/" .. Name]
  end
  
  function Network:RemoteEvent(Name: string): RemoteEvent
    return Net["RE/" .. Name]
  end
  
  function Network:InvokeServer(...): any?
    return CommF:InvokeServer(...)
  end
  
  return Network
end)()

Module.Enemies = (function()
  local EnemiesModule = CreateDictionary({ "__CakePrince", "__PirateRaid", "__RaidBoss", "__Bones", "__Elite", "__Others" }, {})
  
  local Signals = Module.Signals
  local IsAlive = Module.IsAlive
  local SeaCastle = CFrame.new(-5556, 314, -2988)
  
  local Elites = CreateDictionary({ "Deandre", "Diablo", "Urban" }, true)
  local Bones = CreateDictionary({ "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" }, true)
  local CakePrince = CreateDictionary({ "Head Baker", "Baking Staff", "Cake Guard", "Cookie Crafter" }, true)
  
  local Attachment = Instance.new("Attachment") do
    local AlignPosition = Instance.new("AlignPosition")
    AlignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
    AlignPosition.Position = Vector3.new(0, 20, 0)
    AlignPosition.Responsiveness = 200
    AlignPosition.MaxForce = math.huge
    AlignPosition.Parent = Attachment
    AlignPosition.Attachment0 = Attachment
  end
  
  local function newEnemy(List, Enemy)
    if table.find(List, Enemy) then
      return nil
    end
    
    local Humanoid = Enemy:WaitForChild("Humanoid")
    
    if Humanoid and Humanoid.Health > 0 then
      table.insert(List, Enemy)
      Humanoid.Died:Wait()
      table.remove(List, table.find(List, Enemy))
    end
  end
  
  local function PirateRaidEnemy(Enemy)
    local Humanoid = Enemy:WaitForChild("Humanoid")
    
    if not Humanoid or Humanoid.Health <= 0 then
      return nil
    end
    
    local HumanoidRootPart = Enemy:WaitForChild("HumanoidRootPart")
    
    if HumanoidRootPart and (Enemy.Name ~= "rip_indra True Form" and Enemy.Name ~= "Blank Buddy") then
      if (HumanoidRootPart.Position - SeaCastle.Position).Magnitude <= 750 then
        task.spawn(newEnemy, EnemiesModule.__PirateRaid, Enemy)
        Module.PirateRaid = tick()
      end
    end
  end
  
  local function EnemyAdded(Enemy)
    local Name = Enemy.Name
    local Others = EnemiesModule.__Others
    
    if EnemiesModule[`__{Name}`] then
      task.spawn(newEnemy, EnemiesModule[`__{Name}`], Enemy)
    elseif Enemy:GetAttribute("RaidBoss") then
      task.spawn(newEnemy, EnemiesModule.__RaidBoss, Enemy)
    elseif Elites[Name] then
      task.spawn(newEnemy, EnemiesModule.__Elite, Enemy)
    elseif Bones[Name] then
      task.spawn(newEnemy, EnemiesModule.__Bones, Enemy)
    elseif CakePrince[Name] then
      task.spawn(newEnemy, EnemiesModule.__CakePrince, Enemy)
    end
    
    if Module.GameData.Sea == 3 then
      task.spawn(PirateRaidEnemy, Enemy)
    end
    
    Others[Name] = Others[Name] or {}
    task.spawn(newEnemy, Others[Name], Enemy)
  end
  
  function EnemiesModule.IsSpawned(EnemyName: string): boolean
    local Cached = Module.SpawnLocations[EnemyName]
    
    if Cached and Cached.Parent then
      return (Cached:GetAttribute("Active") or EnemiesModule:GetEnemyByTag(EnemyName)) and true or false
    end
    
    return EnemiesModule:GetEnemyByTag(EnemyName) and true or false
  end
  
  function EnemiesModule:GetTagged(TagName: string): table?
    return self[`__{TagName}`] or self.__Others[TagName]
  end
  
  function EnemiesModule:GetEnemyByTag(TagName: string): Model?
    local CachedEnemy = Cached.Enemies[TagName]
    
    if CachedEnemy and IsAlive(CachedEnemy) then
      return CachedEnemy
    end
    
    local Enemies = self:GetTagged(TagName)
    
    if Enemies and #Enemies > 0 then
      for i = 1, #Enemies do
        local Enemy = Enemies[i]
        
        if IsAlive(Enemy) then
          Cached.Enemies[TagName] = Enemy
          return Enemy
        end
      end
    end
  end
  
  function EnemiesModule:GetClosest(Enemies: table): Model?
    local SpecialTag = table.concat(Enemies, ".")
    local CachedEnemy = Cached.Enemies[SpecialTag]
    
    if CachedEnemy and IsAlive(CachedEnemy) then
      return CachedEnemy
    end
    
    local Distance, Nearest = math.huge
    
    for i = 1, #Enemies do
      local Enemy = self:GetClosestByTag(Enemies[i])
      local Magnitude = Enemy and Player:DistanceFromCharacter(Enemy.PrimaryPart.Position)
      
      if Enemy and Magnitude <= Distance then
        Distance, Nearest = Magnitude, Enemy
      end
    end
    
    if Nearest then
      Cached.Enemies[SpecialTag] = Nearest
      return Nearest
    end
  end
  
  function EnemiesModule:GetClosestByTag(TagName: string): Model?
    local CachedEnemy = Cached.Enemies[TagName]
    
    if CachedEnemy and IsAlive(CachedEnemy) then
      return CachedEnemy
    end
    
    local Enemies = self:GetTagged(TagName)
    
    if Enemies and #Enemies > 0 then
      local Distance, Nearest = math.huge
      
      local Position = (Player.Character or Player.CharacterAdded()):GetPivot().Position
      
      for i = 1, #Enemies do
        local Enemy = Enemies[i]
        local PrimaryPart = Enemy.PrimaryPart
        
        if PrimaryPart and IsAlive(Enemy) then
          local Magnitude = (Position - PrimaryPart.Position).Magnitude
          
          if Magnitude <= 15 then
            Cached.Enemies[TagName] = Enemy
            return Enemy
          elseif Magnitude <= Distance then
            Distance, Nearest = Magnitude, Enemy
          end
        end
      end
      
      if Nearest then
        Cached.Enemies[TagName] = Nearest
        return Nearest
      end
    end
  end
  
  for _, Enemy in CollectionService:GetTagged("BasicMob") do EnemyAdded(Enemy) end
  table.insert(Connections, CollectionService:GetInstanceAddedSignal("BasicMob"):Connect(EnemyAdded))
  
  table.insert(Connections, CollectionService:GetInstanceAddedSignal(KILLAURA_TAG):Connect(KillAura))
  table.insert(Connections, CollectionService:GetInstanceAddedSignal(BRING_TAG):Connect(Bring))
  
  return EnemiesModule
end)()

Module.Inventory = (function()
  local Inventory = {
    Unlocked = setmetatable({}, { __index = function() return false end }),
    Mastery = setmetatable({}, { __index = function() return 0 end }),
    Count = setmetatable({}, { __index = function() return 0 end }),
    MasteryRequirements = {},
    Items = {}
  }
  
  function Inventory:UpdateItem(item)
    if type(item) == "table" then
      if item.Type == "Wear" then
        item.Type = "Accessory"
      end
      
      local Name = item.Name
      
      self.Items[Name] = item
      
      if not self.Unlocked[Name] then self.Unlocked[Name] = true end
      if item.Count then self.Count[Name] = item.Count end
      if item.Mastery then self.Mastery[Name] = item.Mastery end
      if item.MasteryRequirements then self.MasteryRequirements[Name] = item.MasteryRequirements end
    end
  end
  
  function Inventory:RemoveItem(ItemName)
    if type(ItemName) == "string" then
      self.Unlocked[ItemName] = nil
      self.Mastery[ItemName] = nil
      self.Count[ItemName] = nil
      self.Items[ItemName] = nil
    end
  end
  
  local function OnClientEvent(Method, ...)
    if Method == "ItemChanged" then
      Inventory:UpdateItem(...)
    elseif Method == "ItemAdded" then
      Inventory:UpdateItem(...)
    elseif Method == "ItemRemoved" then
      Inventory:RemoveItem(...)
    elseif Method == "Notify" then
      Module.Signals.Notify:Fire(...)
    end
  end
  
  task.defer(function()
    table.insert(Connections, CommE.OnClientEvent:Connect(OnClientEvent))
    
    local InventoryData = Module.Network:InvokeServer("getInventory")
    
    for i = 1, #InventoryData do
      Inventory:UpdateItem( InventoryData[i] )
    end
  end)
  
  return Inventory
end)()

Module.Tween = (function()
  local BodyVelocity = Instance.new("BodyVelocity")
  BodyVelocity.Velocity = Vector3.zero
  BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
  BodyVelocity.P = 1000
  
  if _ENV.tween_bodyvelocity then
    _ENV.tween_bodyvelocity:Destroy()
  end
  
  _ENV.tween_bodyvelocity = BodyVelocity
  
  local IsAlive = Module.IsAlive
  
  local BaseParts = {} do
    local function AddObjectToBaseParts(Object)
      if Object:IsA("BasePart") and Object.CanCollide then
        table.insert(BaseParts, Object)
      end
    end
    
    local function RemoveObjectsFromBaseParts(BasePart)
      local index = table.find(BaseParts, BasePart)
      
      if index then
        table.remove(BaseParts, index)
      end
    end
    
    local function NewCharacter(Character)
      table.clear(BaseParts)
      
      for _, Object in ipairs(Character:GetDescendants()) do AddObjectToBaseParts(Object) end
      Character.DescendantAdded:Connect(AddObjectToBaseParts)
      Character.DescendantRemoving:Connect(RemoveObjectsFromBaseParts)
      
      Character:WaitForChild("Humanoid", 9e9).Died:Wait()
      table.clear(BaseParts)
    end
    
    table.insert(Connections, Player.CharacterAdded:Connect(NewCharacter))
    task.spawn(NewCharacter, Player.Character)
  end
  
  local function NoClipOnStepped(Character)
    if not IsAlive(Character) then
      return nil
    end
    
    if _ENV.OnFarm and not Player:HasTag("Teleporting") then
      Player:AddTag("Teleporting")
    elseif not _ENV.OnFarm and Player:HasTag("Teleporting") then
      Player:RemoveTag("Teleporting")
    end
    
    if _ENV.OnFarm then
      for i = 1, #BaseParts do
        local BasePart = BaseParts[i]
        
        if BasePart.CanCollide then
          BasePart.CanCollide = false
        end
      end
    elseif Character.PrimaryPart and (not Character.PrimaryPart.CanCollide or not Character.PrimaryPart.CanTouch) then
      for i = 1, #BaseParts do
        BaseParts[i].CanCollide = true
      end
    end
  end
  
  local function UpdateVelocityOnStepped(Character)
    local RootPart = Character and Character:FindFirstChild("UpperTorso")
    local Humanoid = Character and Character:FindFirstChild("Humanoid")
    local BodyVelocity = _ENV.tween_bodyvelocity
    
    if _ENV.OnFarm and RootPart and Humanoid and Humanoid.Health > 0 then
      if BodyVelocity.Parent ~= RootPart then
        BodyVelocity.Parent = RootPart
      end
    else
      if BodyVelocity.Parent then
        BodyVelocity.Parent = nil
      end
    end
    
    if BodyVelocity.Velocity ~= Vector3.zero and (not Humanoid or not Humanoid.SeatPart or not _ENV.OnFarm) then
      BodyVelocity.Velocity = Vector3.zero
    end
  end
  
  table.insert(Connections, Stepped:Connect(function()
    local Character = Player.Character
    UpdateVelocityOnStepped(Character)
    NoClipOnStepped(Character)
  end))
  
  return BodyVelocity
end)()

-- ============================= --
--	Copyright 2018 FiatAccompli  --
-- ============================= --

-- Search utility for finding shortest path distances on civ 6 maps using uniform cost search.

include("BinaryHeap")
include("SupportFunctions")
include("PlotIterators2")

local UNREACHABLE_DISTANCE = 1000000;
local NO_PREVIOUS_PLOT = -1;

local ADJACENT_PLOT_DIRECTIONS = {
  DirectionTypes.DIRECTION_WEST,
  DirectionTypes.DIRECTION_EAST,
  DirectionTypes.DIRECTION_NORTHWEST,
  DirectionTypes.DIRECTION_NORTHEAST,
  DirectionTypes.DIRECTION_SOUTHWEST,
  DirectionTypes.DIRECTION_SOUTHEAST,
};

DistanceCalculator = { UNREACHABLE_DISTANCE = UNREACHABLE_DISTANCE, NO_PREVIOUS_PLOT = NO_PREVIOUS_PLOT };
DistanceCalculator.__index = DistanceCalculator;

local CONSTANT_PLOT_DISTANCE_CALCULATOR = function(plot, nextPlot, direction, distance)
  return distance + 1;
end

-- Creates a new DistanceCalculator instance where the distance from a plot to a starting point is calculated by 
-- plotDistanceCalculator(plot, adjacentPlot, direction, plotDistance).
function DistanceCalculator:new(plotDistanceCalculator:ifunction)
  local distances = {};
  local previousPlots = {};
  local plotCount = Map.GetPlotCount();
  for i = 0, plotCount - 1 do
    distances[i] = UNREACHABLE_DISTANCE;
    previousPlots[i] = NO_PREVIOUS_PLOT;
  end
  return setmetatable({plotDistanceCalculator = plotDistanceCalculator or CONSTANT_PLOT_DISTANCE_CALCULATOR,
                       distances = distances,
                       previousPlots = previousPlots,
                       startedDistanceCalculations = false,
                       plotQueue = Heap:new()}, 
                      self)
end

-- Adds a plot as a starting point of the search with implied initial cost to get to the plot.
-- (Another way of looking at it is that the true start node for path finding is off the map and calling this 
-- adds an edge from it to <plot> of length <initialDistance>.)
function DistanceCalculator:AddStartPlot(plot:table, initialDistance:number)
  assert(not self.startedDistanceCalculations, "Can not add plot after starting to compute distances");
  initialDistance = initialDistance or 0;

  local plotIndex = plot:GetIndex();

  if initialDistance < self.distances[plotIndex] then
    self.distances[plotIndex] = initialDistance;
    self.previousPlots[plotIndex] = NO_PREVIOUS_PLOT;
    self.plotQueue:Insert(initialDistance, plot);
  end
end

function DistanceCalculator:ComputeForAllPlots()
  self.startedDistanceCalculations = true;

  while not self.plotQueue:IsEmpty() do
    local distance, plot = self.plotQueue:Pop();
    local plotIndex = plot:GetIndex();

    -- Don't need to do anything if we're seeing this plot through a non-shortest path since we will
    -- have already processed it through a shorter path.
    if distance <= self.distances[plotIndex] then
      local x = plot:GetX();
      local y = plot:GetY();

      for _, direction in ipairs(ADJACENT_PLOT_DIRECTIONS) do
        local nextPlot = Map.GetAdjacentPlot(x, y, direction);
        -- Skip plots that fall off the edge of the world.
        if nextPlot ~= nil then
          local nextPlotIndex = nextPlot:GetIndex();
          -- Also skip doing distance calculation (which might be somewhat expensive) when 
          -- we know it will not be better than what we already have for a plot.
          if distance < self.distances[nextPlotIndex] then
            local nextPlotDistance = self.plotDistanceCalculator(plot, nextPlot, direction, distance);
            assert(nextPlotDistance >= distance, "calculated plot to plot distance is negative " .. tostring(distance) .. "->" .. tostring(nextPlotDistance));

            -- Also skip the plot if it is unreachable from the current one.
            if nextPlotDistance < UNREACHABLE_DISTANCE then
              if nextPlotDistance < self.distances[nextPlotIndex] then
                self.distances[nextPlotIndex] = nextPlotDistance;
                self.previousPlots[nextPlotIndex] = plotIndex;
                self.plotQueue:Insert(nextPlotDistance, nextPlot);
              end
            end 
          end
        end
      end
    end
  end
end

-- Show computed paths/distances on screen in world view.  (Use from LiveTuner, must be in ui script context to use.)
function DistanceCalculator:DebugShowOnWorldMap(distanceMultiplier)
  -- Since UI.AddNumberToPath only shows the whole part of the number, multiply each distance 
  -- so that fractional parts are visible (e.g. roads use a fraction of a movement point in later eras).
  distanceMultiplier = distanceMultiplier or 10;

  UILens.SetActive(LensLayers.TRADE_ROUTE);
  UILens.SetActive(LensLayers.NUMBERS);
  UILens.ClearLayerHexes(LensLayers.TRADE_ROUTE);
  UILens.ClearLayerHexes(LensLayers.NUMBERS);

  local color = RGBAValuesToABGRHex(0.088,0.043,0.168,1.0)

  -- Why not just draw the previous plot (e.g. shortest path) mapping for every plot and let the core game engine
  -- handle what shows up on screen like it does for everything else.  Because bad stuff happens when you exceed ~1000 
  -- trade route or movement path segments.  First the game simply will simply ignore additions once you get beyond 
  -- ~1000 paths (it actually seems to be 963, but why that number would be a limit I have no idea) (or maybe it's path
  -- segments that are the limit, but this use has a one to one correspondence between them, so it doesn't really matter
  -- which it is).  To stay safely within the limit we have to restrict to drawing the paths only for the hexes that are 
  -- on-screen (or right next to it.)  Furthermore, once the ~1000 paths limit is exceeded the game has a nasty habit of
  -- crashing when trying to end the game (either through a reload, or exit to menu/desktop).
  for plotIndex in PlotIterators.AndAdjacentIndexIterator(PlotIterators.OnScreenIndexIterator()) do
    local plot = Map.GetPlotByIndex(plotIndex); --= Map.GetPlot(x, y);
    if self.distances[plotIndex] < UNREACHABLE_DISTANCE then 
      UI.AddNumberToPath(self.distances[plotIndex] * distanceMultiplier, plotIndex);
      if self.previousPlots[plotIndex] ~= NO_PREVIOUS_PLOT then
        UILens.SetLayerHexesPath(LensLayers.TRADE_ROUTE, Game.GetLocalPlayer(), {self.previousPlots[plotIndex], plotIndex}, {}, color);
      end
    end
  end
end
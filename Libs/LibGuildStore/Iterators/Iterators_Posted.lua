local internal = _G["LibGuildStore_Internal"]
local posted_items_data = _G["LibGuildStore_PostedItemsData"]
local pir_index = _G["LibGuildStore_PostedItemsIndex"]

function internal:CheckForDuplicatePostedItem(itemLink, eventID)
  local theIID = GetItemLinkItemId(itemLink)
  if theIID == nil or theIID == 0 then return end
  local itemIndex = internal.GetOrCreateIndexFromLink(itemLink)

  if posted_items_data[theIID] and posted_items_data[theIID][itemIndex] then
    for _, v in pairs(posted_items_data[theIID][itemIndex]['sales']) do
      if v.id == eventID then
        return true
      end
    end
  end
  return false
end

----------------------------------------
----- Reference Posted Items       -----
----------------------------------------

function internal:addPostedItem(theEvent)
  --internal:dm("Debug", "addPostedItem")
  if not MasterMerchant.isInitialized then return end
  --[[
          local theEvent            = {
            guild = guildHash,
            itemLink = linkHash,
            quant = stackCount,
            timestamp = GetTimeStamp(),
            price = price,
            seller = sellerHash,
            buyer
          }
  ]]--
  local eventItemLink = theEvent.itemLink
  local eventSeller = theEvent.seller
  local eventGuild = theEvent.guild
  local timestamp = theEvent.timestamp

  -- first add new data lookups to their tables
  local linkHash = internal:AddSalesTableData("itemLink", eventItemLink)
  local sellerHash = internal:AddSalesTableData("accountNames", eventSeller)
  local guildHash = internal:AddSalesTableData("guildNames", eventGuild)
  local formattedItemName = zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(eventItemLink))

  --[[The quality effects itemIndex although the ID from the
  itemLink may be the same. We will keep them separate.
  ]]--
  local itemIndex = internal.GetOrCreateIndexFromLink(eventItemLink)

  --[[theIID is used in wordData for the SRIndex, define it here.
  ]]--
  local theIID = GetItemLinkItemId(eventItemLink)
  if theIID == nil or theIID == 0 then return false end

  --[[If the ID from the itemLink doesn't exist determine which
  file or container it will belong to using SetGuildStoreData()
  ]]--
  if not posted_items_data[theIID] then
    posted_items_data[theIID] = internal:SetPostedItmesData(theIID)
  end
  posted_items_data[theIID][itemIndex] = posted_items_data[theIID][itemIndex] or {}
  posted_items_data[theIID][itemIndex].itemIcon = posted_items_data[theIID][itemIndex].itemIcon or GetItemLinkInfo(eventItemLink)
  posted_items_data[theIID][itemIndex].itemAdderText = posted_items_data[theIID][itemIndex].itemAdderText or internal:AddSearchToItem(eventItemLink)
  posted_items_data[theIID][itemIndex].itemDesc = posted_items_data[theIID][itemIndex].itemDesc or formattedItemName
  posted_items_data[theIID][itemIndex].totalCount = posted_items_data[theIID][itemIndex].totalCount or 0 -- assign count if if new sale
  posted_items_data[theIID][itemIndex].totalCount = posted_items_data[theIID][itemIndex].totalCount + 1 -- increment count if existing sale
  posted_items_data[theIID][itemIndex].wasAltered = true
  posted_items_data[theIID][itemIndex]['sales'] = posted_items_data[theIID][itemIndex]['sales'] or {}
  local searchItemDesc = posted_items_data[theIID][itemIndex].itemDesc -- used for searchText
  local searchItemAdderText = posted_items_data[theIID][itemIndex].itemAdderText -- used for searchText

  theEvent.itemLink = linkHash
  theEvent.seller = sellerHash
  theEvent.guild = guildHash

  local insertedIndex = 1
  local salesTable = posted_items_data[theIID][itemIndex]['sales']
  local nextLocation = #salesTable + 1
  if salesTable[nextLocation] == nil then
    table.insert(salesTable, nextLocation, theEvent)
    insertedIndex = nextLocation
  else
    table.insert(salesTable, theEvent)
    insertedIndex = #salesTable
  end

  local newestTime = posted_items_data[theIID][itemIndex]["newestTime"]
  local oldestTime = posted_items_data[theIID][itemIndex]["oldestTime"]
  if newestTime == nil or newestTime < timestamp then posted_items_data[theIID][itemIndex]["newestTime"] = timestamp end
  if oldestTime == nil or oldestTime > timestamp then posted_items_data[theIID][itemIndex]["oldestTime"] = timestamp end

  local temp = { '', ' ', '', ' ', '', ' ', '', } -- fewer tokens for posted items

  temp[1] = eventSeller and ('s' .. eventSeller) or ''
  temp[3] = eventGuild or ''
  temp[5] = searchItemDesc or ''
  temp[7] = searchItemAdderText or ''
  local searchText = zo_strlower(table.concat(temp, ''))

  local searchByWords = zo_strgmatch(searchText, '%S+')
  local wordData = { theIID, itemIndex, insertedIndex }

  -- Index each word
  for i in searchByWords do
    pir_index[i] = pir_index[i] or {}
    table.insert(pir_index[i], wordData)
    internal.pir_index_count = (internal.pir_index_count or 0) + 1
  end

  return true
end

----------------------------------------
----- iterateOverPostedItemsData  -----
----------------------------------------

function internal:iterateOverPostedItemsData(itemid, versionid, saleid, prefunc, loopfunc, postfunc, extraData)
  extraData.versionCount = (extraData.versionCount or 0)
  extraData.idCount = (extraData.idCount or 0)
  extraData.checkMilliseconds = (extraData.checkMilliseconds or MM_WAIT_TIME_IN_MILLISECONDS_DEFAULT)

  if prefunc then
    prefunc(extraData)
  end

  local checkTime = GetGameTimeMilliseconds()
  local versionlist
  local itemLink
  if itemid == nil then
    itemid, versionlist = next(posted_items_data, itemid)
    extraData.versionRemoved = false
    versionid = nil
  else
    versionlist = posted_items_data[itemid]
  end
  while (itemid ~= nil) do
    local versiondata
    if versionid == nil then
      versionid, versiondata = next(versionlist, versionid)
      extraData.saleRemoved = false
      saleid = nil
    else
      versiondata = versionlist[versionid]
    end
    itemLink = nil
    --[[ begin loop over ['x:x:x:x:x'] ]]--
    while (versionid ~= nil) do
      if versiondata['sales'] then
        local saledata
        if saleid == nil then
          saleid, saledata = next(versiondata['sales'], saleid)
        else
          saledata = versiondata['sales'][saleid]
        end
        if not itemLink and saledata and saledata["itemLink"] then itemLink = internal:GetItemLinkByIndex(saledata["itemLink"]) end
        --[[ begin loop over ['sales'] ]]--
        while (saleid ~= nil) do
          --[[skipTheRest is true here from Truncate Sales because in that function
          you are looping over all the sales. Normally you are not and only processing
          a single sale. Therefore when skipTheRest is false you use:

          saleid, saledata = next(versiondata['sales'], saleid)

          to get the next sale and process it
          ]]--
          local skipTheRest = loopfunc(itemid, versionid, versiondata, saleid, saledata, extraData)
          extraData.saleRemoved = extraData.saleRemoved or (versiondata['sales'][saleid] == nil)
          if skipTheRest then
            saleid = nil
          else
            saleid, saledata = next(versiondata['sales'], saleid)
          end
          -- We've run out of time, wait and continue with next sale
          if saleid and (GetGameTimeMilliseconds() - checkTime) > extraData.checkMilliseconds then
            local LEQ = LibExecutionQueue:new()
            LEQ:continueWith(function() internal:iterateOverPostedItemsData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
            return
          end
        end
        --[[ end of loop over ['sales'] ]]--

        if extraData.saleRemoved then
          local sales = {}
          local salesCount = 0
          extraData.newSalesCount = nil
          for _, sd in pairs(versiondata['sales']) do
            if (sd ~= nil) and (type(sd) == 'table') then
              table.insert(sales, sd)
              salesCount = salesCount + 1
            end
          end
          versiondata['sales'] = sales
          versiondata["totalCount"] = salesCount
        end

        if extraData.newSalesCount then
          versiondata["totalCount"] = extraData.newSalesCount
        end
      end

      -- If we just deleted all the sales, clear the bucket out
      if (versionlist[versionid] ~= nil and ((versiondata['sales'] == nil) or (versiondata["totalCount"] < 1) or (not zo_strmatch(tostring(versionid), "^%d+:%d+:%d+:%d+:%d+")))) then
        extraData.versionCount = (extraData.versionCount or 0) + 1
        versionlist[versionid] = nil
        extraData.versionRemoved = true
      end

      -- Sharlikran
      if LibGuildStore_SavedVariables["updateAdditionalText"] and not extraData.saleRemoved then
        if itemLink then
          versiondata['itemAdderText'] = internal:AddSearchToItem(itemLink)
          versiondata['itemDesc'] = zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(itemLink))
        end
      end

      -- Sharlikran
      if extraData.wasAltered and not extraData.saleRemoved then
        versiondata["wasAltered"] = true
        extraData.wasAltered = false
      end

      -- Go onto the next Version
      versionid, versiondata = next(versionlist, versionid)
      extraData.saleRemoved = false
      extraData.newSalesCount = nil
      saleid = nil
      if versionid and (GetGameTimeMilliseconds() - checkTime) > extraData.checkMilliseconds then
        local LEQ = LibExecutionQueue:new()
        LEQ:continueWith(function() internal:iterateOverPostedItemsData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
        return
      end
    end
    --[[ end loop over ['x:x:x:x:x'] ]]--

    if extraData.versionRemoved then
      local versions = {}
      for vid, vd in pairs(posted_items_data[itemid]) do
        if (vd ~= nil) and (type(vd) == 'table') then
          versions[vid] = vd
        end
      end
      posted_items_data[itemid] = versions
    end

    -- If we just deleted everything, clear the bucket out
    if (posted_items_data[itemid] ~= nil and ((internal:NonContiguousNonNilCount(versionlist) < 1) or (type(itemid) ~= 'number'))) then
      extraData.idCount = (extraData.idCount or 0) + 1
      posted_items_data[itemid] = nil
    end

    -- Go on to the next Item
    itemid, versionlist = next(posted_items_data, itemid)
    extraData.versionRemoved = false
    versionid = nil
  end

  if postfunc then
    postfunc(extraData)
  end
end

function internal:TruncatePostedItemsHistory()
  internal:dm("Debug", "TruncatePostedItemsHistory")

  -- DEBUG  TruncatePostedItemsHistory
  -- do return end

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.deleteCount = 0
    extraData.newSalesCount = 0
    extraData.epochBack = GetTimeStamp() - (ZO_ONE_DAY_IN_SECONDS * LibGuildStore_SavedVariables["historyDepthPI"])
    extraData.wasAltered = false

    internal:DatabaseBusy(true)
  end

  local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)

    local salesDeleted = 0
    local salesCount = versiondata.totalCount
    if salesCount == 0 then
      versiondata['sales'] = {}
      extraData.saleRemoved = false
      return true
    end
    local salesDataTable = internal:spairs(versiondata['sales'], function(a, b) return internal:CleanTimestamp(a) < internal:CleanTimestamp(b) end)
    for salesId, salesData in salesDataTable do
      if (salesData['timestamp'] < extraData.epochBack
        or salesData['timestamp'] == nil
        or type(salesData['timestamp']) ~= 'number'
      ) then
        -- Remove it by setting it to nil
        versiondata['sales'][salesId] = nil
        salesDeleted = salesDeleted + 1
        extraData.wasAltered = true
        salesCount = salesCount - 1
      end
    end
    extraData.deleteCount = extraData.deleteCount + salesDeleted
    extraData.newSalesCount = salesCount
    --[[ `for saleid, saledata in salesDataTable do` is not a loop
    to Lua so we can not get the oldest time of the first element
    and break. Mark the list altered and clean up in RenewExtraData.

    Also since we have to get the new oldest time, renew the totalCount
    with RenewExtraData also.
    ]]--
    return true
  end

  local postfunc = function(extraData)
    internal:DatabaseBusy(false)
    if LibGuildStore_SavedVariables["showTruncateSummary"] then
      internal:dm("Info", string.format(GetString(GS_TRUNCATE_POSTED_COMPLETE), GetTimeStamp() - extraData.start, extraData.deleteCount))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverPostedItemsData(nil, nil, nil, prefunc, loopfunc, postfunc, {})
  end

end

function internal:IndexPostedItemsData()
  internal:dm("Debug", "IndexPostedItemsData")

  -- DEBUG  Stop Indexing
  --do return end

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.checkMilliseconds = MM_WAIT_TIME_IN_MILLISECONDS_SHORT
    extraData.indexCount = 0
    extraData.wordsIndexCount = 0
    extraData.wasAltered = false
    internal:DatabaseBusy(true)
  end

  local loopfunc = function(numberID, itemData, versiondata, itemIndex, postedItem, extraData)

    extraData.indexCount = extraData.indexCount + 1

    local currentItemLink = internal:GetItemLinkByIndex(postedItem['itemLink'])
    local currentGuild = internal:GetGuildNameByIndex(postedItem['guild'])
    local currentSeller = internal:GetAccountNameByIndex(postedItem['seller'])

    versiondata.itemAdderText = versiondata.itemAdderText or self.addedSearchToItem(currentItemLink)
    versiondata.itemDesc = versiondata.itemDesc or zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(currentItemLink))
    versiondata.itemIcon = versiondata.itemIcon or GetItemLinkInfo(currentItemLink)

    local temp = { '', ' ', '', ' ', '', ' ', '', } -- fewer tokens for posted items

    temp[1] = currentSeller and ('s' .. currentSeller) or ''
    temp[3] = currentGuild or ''
    temp[5] = versiondata.itemDesc or ''
    temp[7] = versiondata.itemAdderText or ''

    local searchText = zo_strlower(table.concat(temp, ''))
    local searchByWords = zo_strgmatch(searchText, '%S+')
    local wordData = { numberID, itemData, itemIndex }

    -- Index each word
    for i in searchByWords do
      pir_index[i] = pir_index[i] or {}
      table.insert(pir_index[i], wordData)
      extraData.wordsIndexCount = (extraData.wordsIndexCount or 0) + 1
      internal.pir_index_count = (internal.pir_index_count or 0) + 1
    end
  end

  local postfunc = function(extraData)
    internal:DatabaseBusy(false)
    if LibGuildStore_SavedVariables["showIndexingSummary"] then
      internal:dm("Info", string.format(GetString(GS_INDEXING_SUMMARY), GetTimeStamp() - extraData.start, extraData.indexCount, extraData.wordsIndexCount))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverPostedItemsData(nil, nil, nil, prefunc, loopfunc, postfunc, {})
  end

end

function internal:InitPostedItemsHistory()
  internal:dm("Debug", "InitPostedItemsHistory")

  local extradata = {}

  if internal.postedItems == nil then
    internal.postedItems = {}
    extradata.doPostedItems = true
  end

  if internal.postedSellers == nil then
    internal.postedSellers = {}
    extradata.doPostedSellers = true
  end

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    internal:DatabaseBusy(true)
    extraData.totalRecords = 0
  end

  local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)
    extraData.totalRecords = extraData.totalRecords + 1
    local currentGuild = internal:GetGuildNameByIndex(saledata['guild'])
    if currentGuild then
      local currentSeller = internal:GetAccountNameByIndex(saledata['seller'])

      if (extradata.doPostedItems) then
        if not internal.postedItems[currentGuild] then
          internal.postedItems[currentGuild] = MMGuild:new(currentGuild)
        end
        local _, firstsaledata = next(versiondata.sales, nil)
        local firstsaledataItemLink = internal:GetItemLinkByIndex(firstsaledata.itemLink)
        local searchDataDesc = versiondata.itemDesc or zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(firstsaledataItemLink))
        local searchDataAdder = versiondata.itemAdderText or internal:AddSearchToItem(firstsaledataItemLink)
        local searchData = searchDataDesc .. ' ' .. searchDataAdder
        local guild = internal.postedItems[currentGuild]
        guild:addPurchaseByDate(firstsaledataItemLink, saledata.timestamp, saledata.price, saledata.quant, false, nil, searchData)
      end

      if (extradata.doPostedSellers) then
        if not internal.postedSellers[currentGuild] then
          internal.postedSellers[currentGuild] = MMGuild:new(currentGuild)
        end
        local guild = internal.postedSellers[currentGuild]
        guild:addPurchaseByDate(currentSeller, saledata.timestamp, saledata.price, saledata.quant, false, nil)
      end

    end
    return false
  end

  local postfunc = function(extraData)

    for _, guild in pairs(internal.postedItems) do
      guild:SortAllRanks()
    end

    for _, guild in pairs(internal.postedSellers) do
      guild:SortAllRanks()
    end

    internal:DatabaseBusy(false)

    internal.totalPosted = extraData.totalRecords
    if LibGuildStore_SavedVariables["showGuildInitSummary"] then
      internal:dm("Info", string.format(GetString(GS_INIT_LISTINGS_HISTORY_SUMMARY), GetTimeStamp() - extraData.start,
        internal.totalPosted))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverPostedItemsData(nil, nil, nil, prefunc, loopfunc, postfunc, extradata)
  end

end

function internal:ReferencePostedItemsDataContainer()
  internal:dm("Debug", "Reference Posted Items Data Container")
  local savedVars = GS17DataSavedVariables[internal.postedNamespace]
  for itemid, versionlist in pairs(savedVars) do
    if posted_items_data[itemid] then
      for versionid, versiondata in pairs(versionlist) do
        if posted_items_data[itemid][versionid] then
          if versiondata['sales'] then
            posted_items_data[itemid][versionid]['sales'] = posted_items_data[itemid][versionid]['sales'] or {}
            -- IPAIRS
            for saleid, saledata in pairs(versiondata['sales']) do
              if (type(saleid) == 'number' and type(saledata) == 'table' and type(saledata.timestamp) == 'number') then
                table.insert(posted_items_data[itemid][versionid]['sales'], saledata)
              end
            end
            local _, first = next(versiondata['sales'], nil)
            if first then
              posted_items_data[itemid][versionid].itemIcon = GetItemLinkInfo(first.itemLink)
              posted_items_data[itemid][versionid].itemAdderText = internal:AddSearchToItem(first.itemLink)
              posted_items_data[itemid][versionid].itemDesc = zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(first.itemLink))
            end
          end
        else
          posted_items_data[itemid][versionid] = versiondata
        end
      end
      savedVars[itemid] = nil
    else
      posted_items_data[itemid] = versionlist
    end
  end
end

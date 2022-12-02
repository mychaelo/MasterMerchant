local internal = _G["LibGuildStore_Internal"]
local cancelled_items_data = _G["LibGuildStore_CancelledItemsData"]
local cr_index = _G["LibGuildStore_CancelledItemsIndex"]

function internal:CheckForDuplicateCancelledItem(itemLink, eventID)
  local theIID = GetItemLinkItemId(itemLink)
  if theIID == nil or theIID == 0 then return end
  local itemIndex = internal.GetOrCreateIndexFromLink(itemLink)

  if cancelled_items_data[theIID] and cancelled_items_data[theIID][itemIndex] then
    for _, v in pairs(cancelled_items_data[theIID][itemIndex]['sales']) do
      if v.id == eventID then
        return true
      end
    end
  end
  return false
end

function internal:addCancelledItem(theEvent)
  --internal:dm("Debug", "addCancelledItem")
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
  --internal:dm("Debug", theEvent)
  local linkHash = internal:AddSalesTableData("itemLink", theEvent.itemLink)
  local sellerHash = internal:AddSalesTableData("accountNames", theEvent.seller)
  local guildHash = internal:AddSalesTableData("guildNames", theEvent.guild)

  local itemIndex = internal.GetOrCreateIndexFromLink(theEvent.itemLink)
  local theIID = GetItemLinkItemId(theEvent.itemLink)
  if theIID == nil or theIID == 0 then return false end

  if not cancelled_items_data[theIID] then
    cancelled_items_data[theIID] = internal:SetCancelledItmesData(theIID)
  end
  local newEvent = ZO_DeepTableCopy(theEvent)
  newEvent.itemLink = linkHash
  newEvent.seller = sellerHash
  newEvent.guild = guildHash

  local insertedIndex = 1
  local searchItemDesc = ""
  local searchItemAdderText = ""
  if cancelled_items_data[theIID][itemIndex] then
    searchItemDesc = cancelled_items_data[theIID][itemIndex].itemDesc
    searchItemAdderText = cancelled_items_data[theIID][itemIndex].itemAdderText
    table.insert(cancelled_items_data[theIID][itemIndex]['sales'], newEvent)
    insertedIndex = #cancelled_items_data[theIID][itemIndex]['sales']
  else
    if cancelled_items_data[theIID][itemIndex] == nil then cancelled_items_data[theIID][itemIndex] = {} end
    if cancelled_items_data[theIID][itemIndex]['sales'] == nil then cancelled_items_data[theIID][itemIndex]['sales'] = {} end
    searchItemDesc = zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(theEvent.itemLink))
    searchItemAdderText = internal:AddSearchToItem(theEvent.itemLink)
    cancelled_items_data[theIID][itemIndex] = {
      itemIcon = GetItemLinkInfo(theEvent.itemLink),
      itemAdderText = searchItemAdderText,
      itemDesc = searchItemDesc,
      sales = { newEvent } }
    --internal:dm("Debug", newEvent)
  end
  cancelled_items_data[theIID][itemIndex].wasAltered = true
  if cancelled_items_data[theIID][itemIndex] and cancelled_items_data[theIID][itemIndex].totalCount then
    cancelled_items_data[theIID][itemIndex].totalCount = cancelled_items_data[theIID][itemIndex].totalCount + 1
  else
    cancelled_items_data[theIID][itemIndex].totalCount = 1
  end

  local playerName = zo_strlower(GetDisplayName())
  local isSelfSale = playerName == zo_strlower(theEvent.seller)

  local temp = { '', ' ', '', ' ', '', ' ', '', ' ', '', ' ', '', }
  local searchText = ""
  if LibGuildStore_SavedVariables["minimalIndexing"] then
    if isSelfSale then
      searchText = internal.PlayerSpecialText
    end
  else
    if theEvent.buyer then temp[1] = 'b' .. theEvent.buyer end
    if theEvent.seller then temp[3] = 's' .. theEvent.seller end
    temp[5] = theEvent.guild or ''
    temp[7] = searchItemDesc or ''
    temp[9] = searchItemAdderText or ''
    if isSelfSale then
      temp[11] = internal.PlayerSpecialText
    end
    searchText = zo_strlower(table.concat(temp, ''))
  end

  local searchByWords = zo_strgmatch(searchText, '%S+')
  local wordData = { theIID, itemIndex, insertedIndex }

  -- Index each word
  for i in searchByWords do
    if cr_index[i] == nil then cr_index[i] = {} end
    table.insert(cr_index[i], wordData)
    internal.cr_index_count = internal.cr_index_count + 1
  end

  return true
end

----------------------------------------
----- iterateOverCancelledItemData  -----
----------------------------------------

function internal:iterateOverCancelledItemData(itemid, versionid, saleid, prefunc, loopfunc, postfunc, extraData)
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
    itemid, versionlist = next(cancelled_items_data, itemid)
    extraData.versionRemoved = false
    versionid = nil
  else
    versionlist = cancelled_items_data[itemid]
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
            LEQ:ContinueWith(function() internal:iterateOverCancelledItemData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
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
        LEQ:ContinueWith(function() internal:iterateOverCancelledItemData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
        return
      end
    end
    --[[ end loop over ['x:x:x:x:x'] ]]--

    if extraData.versionRemoved then
      local versions = {}
      for vid, vd in pairs(cancelled_items_data[itemid]) do
        if (vd ~= nil) and (type(vd) == 'table') then
          versions[vid] = vd
        end
      end
      cancelled_items_data[itemid] = versions
    end

    -- If we just deleted everything, clear the bucket out
    if (cancelled_items_data[itemid] ~= nil and ((internal:NonContiguousNonNilCount(versionlist) < 1) or (type(itemid) ~= 'number'))) then
      extraData.idCount = (extraData.idCount or 0) + 1
      cancelled_items_data[itemid] = nil
    end

    -- Go on to the next Item
    itemid, versionlist = next(cancelled_items_data, itemid)
    extraData.versionRemoved = false
    versionid = nil
  end

  if postfunc then
    postfunc(extraData)
  end
end

function internal:TruncateCancelledItemHistory()
  internal:dm("Debug", "TruncateCancelledItemHistory")

  -- DEBUG  TruncateCancelledItemHistory
  -- do return end

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.deleteCount = 0
    extraData.newSalesCount = 0
    extraData.epochBack = GetTimeStamp() - (ZO_ONE_DAY_IN_SECONDS * LibGuildStore_SavedVariables["historyDepthCI"])
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
      internal:dm("Info", string.format(GetString(GS_TRUNCATE_CANCELLED_COMPLETE), GetTimeStamp() - extraData.start, extraData.deleteCount))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverCancelledItemData(nil, nil, nil, prefunc, loopfunc, postfunc, {})
  end

end

function internal:IndexCancelledItemData()
  internal:dm("Debug", "IndexCancelledItemData")

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

  local loopfunc = function(numberID, itemData, versiondata, itemIndex, cancelledItem, extraData)

    extraData.indexCount = extraData.indexCount + 1

    local currentItemLink = internal:GetItemLinkByIndex(cancelledItem['itemLink'])
    local currentGuild = internal:GetGuildNameByIndex(cancelledItem['guild'])
    local currentSeller = internal:GetAccountNameByIndex(cancelledItem['seller'])

    local playerName = zo_strlower(GetDisplayName())
    local selfSale = playerName == zo_strlower(currentSeller)
    local searchText = ""
    if LibGuildStore_SavedVariables["minimalIndexing"] then
      if selfSale then
        searchText = internal.PlayerSpecialText
      end
    else
      versiondata.itemAdderText = versiondata.itemAdderText or self.addedSearchToItem(currentItemLink)
      versiondata.itemDesc = versiondata.itemDesc or zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(currentItemLink))
      versiondata.itemIcon = versiondata.itemIcon or GetItemLinkInfo(currentItemLink)

      local temp = { '', ' ', '', ' ', '', ' ', '', ' ', '', ' ', '', }
      if currentSeller then temp[3] = 's' .. currentSeller end
      temp[5] = currentGuild or ''
      temp[7] = versiondata.itemDesc or ''
      temp[9] = versiondata.itemAdderText or ''
      if selfSale then
        temp[11] = internal.PlayerSpecialText
      end
      searchText = zo_strlower(table.concat(temp, ''))
    end

    -- Index each word
    local searchByWords = zo_strgmatch(searchText, '%S+')
    local wordData = { numberID, itemData, itemIndex }
    for i in searchByWords do
      if cr_index[i] == nil then
        extraData.wordsIndexCount = extraData.wordsIndexCount + 1
        cr_index[i] = {}
      end
      table.insert(cr_index[i], wordData)
      internal.cr_index_count = internal.cr_index_count + 1
    end

  end

  local postfunc = function(extraData)
    internal:DatabaseBusy(false)
    if LibGuildStore_SavedVariables["showIndexingSummary"] then
      internal:dm("Info", string.format(GetString(GS_INDEXING_SUMMARY), GetTimeStamp() - extraData.start, extraData.indexCount, extraData.wordsIndexCount))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverCancelledItemData(nil, nil, nil, prefunc, loopfunc, postfunc, {})
  end

end

function internal:InitCancelledItemsHistory()
  internal:dm("Debug", "InitCancelledItemsHistory")

  local extradata = {}

  if internal.cancelledItems == nil then
    internal.cancelledItems = {}
    extradata.doCancelledItems = true
  end

  if internal.cancelledSellers == nil then
    internal.cancelledSellers = {}
    extradata.doCancelledSellers = true
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

      if (extradata.doCancelledItems) then
        if not internal.cancelledItems[currentGuild] then
          internal.cancelledItems[currentGuild] = MMGuild:new(currentGuild)
        end
        local _, firstsaledata = next(versiondata.sales, nil)
        local firstsaledataItemLink = internal:GetItemLinkByIndex(firstsaledata.itemLink)
        local searchDataDesc = versiondata.itemDesc or zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(firstsaledataItemLink))
        local searchDataAdder = versiondata.itemAdderText or internal:AddSearchToItem(firstsaledataItemLink)
        local searchData = searchDataDesc .. ' ' .. searchDataAdder
        local guild = internal.cancelledItems[currentGuild]
        guild:addPurchaseByDate(firstsaledataItemLink, saledata.timestamp, saledata.price, saledata.quant, false, nil, searchData)
      end

      if (extradata.doCancelledSellers) then
        if not internal.cancelledSellers[currentGuild] then
          internal.cancelledSellers[currentGuild] = MMGuild:new(currentGuild)
        end
        local guild = internal.cancelledSellers[currentGuild]
        guild:addPurchaseByDate(currentSeller, saledata.timestamp, saledata.price, saledata.quant, false, nil)
      end

    end
    return false
  end

  local postfunc = function(extraData)

    for _, guild in pairs(internal.cancelledItems) do
      guild:SortAllRanks()
    end

    for _, guild in pairs(internal.cancelledSellers) do
      guild:SortAllRanks()
    end

    internal:DatabaseBusy(false)

    internal.totalCanceled = extraData.totalRecords
    if LibGuildStore_SavedVariables["showGuildInitSummary"] then
      internal:dm("Info", string.format(GetString(GS_INIT_LISTINGS_HISTORY_SUMMARY), GetTimeStamp() - extraData.start, internal.totalCanceled))
    end
  end

  if not internal.isDatabaseBusy then
    internal:iterateOverCancelledItemData(nil, nil, nil, prefunc, loopfunc, postfunc, extradata)
  end

end

function internal:ReferenceCancelledItemDataContainer()
  internal:dm("Debug", "Reference Cancelled Item Data Container")
  local savedVars = GS17DataSavedVariables[internal.cancelledNamespace]
  for itemid, versionlist in pairs(savedVars) do
    if cancelled_items_data[itemid] then
      for versionid, versiondata in pairs(versionlist) do
        if cancelled_items_data[itemid][versionid] then
          if versiondata['sales'] then
            cancelled_items_data[itemid][versionid]['sales'] = cancelled_items_data[itemid][versionid]['sales'] or {}
            -- IPAIRS
            for saleid, saledata in pairs(versiondata['sales']) do
              if (type(saleid) == 'number' and type(saledata) == 'table' and type(saledata.timestamp) == 'number') then
                table.insert(cancelled_items_data[itemid][versionid]['sales'], saledata)
              end
            end
            local _, first = next(versiondata['sales'], nil)
            if first then
              cancelled_items_data[itemid][versionid].itemIcon = GetItemLinkInfo(first.itemLink)
              cancelled_items_data[itemid][versionid].itemAdderText = internal:AddSearchToItem(first.itemLink)
              cancelled_items_data[itemid][versionid].itemDesc = zo_strformat(SI_TOOLTIP_ITEM_NAME, GetItemLinkName(first.itemLink))
            end
          end
        else
          cancelled_items_data[itemid][versionid] = versiondata
        end
      end
      savedVars[itemid] = nil
    else
      cancelled_items_data[itemid] = versionlist
    end
  end
end

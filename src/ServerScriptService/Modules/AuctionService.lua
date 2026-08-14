--[[
	AuctionService
	The auction house floor. Server-authoritative, like everything that touches
	money.

	The shape of a lot:

	  - Consigning REMOVES the brainrot from your inventory. It isn't yours and
	    isn't the buyer's; the lot holds it. That's what makes listing a real
	    decision rather than free upside -- a listed brainrot is off its pad and
	    paying you nothing while it sits on the block.

	  - The house always has a standing bid (Auction.floorPrice), so a lot in an
	    empty server still sells. Players bid on top of it.

	  - Player bids are ESCROWED: the money leaves your wallet when you bid and
	    comes back the moment someone outbids you. Checking affordability only
	    at settlement would let one player park a huge bid, spend the money
	    elsewhere, and win the lot with an empty wallet.

	The two paths that leak an economy are disconnect and shutdown, so they are
	built in rather than bolted on:

	  - Seller leaves -> the lot is cancelled, the item goes back to their
	    inventory and the standing bidder is refunded. Connected BEFORE
	    DataService.release in Bootstrap, so the returned item is in the profile
	    that gets saved.
	  - Bidder leaves -> refunded, and the lot falls back to the next bid down
	    (which is always at least the house floor, so it never falls through).
	  - Server closes -> BindToClose settles every open lot immediately.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Auction = require(Shared.Auction)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Brainrots = require(Shared.Brainrots)

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local PlotService = require(script.Parent.PlotService)

local AuctionService = {}

local lots = {} -- [lotId] = lot
local nextLotId = 1

-- Set by HubService once the consign desk exists. Nil until then, which
-- fail-OPENS in exactly one direction: see nearDesk.
AuctionService.desk = nil

-- ── helpers ─────────────────────────────────────────────────────────────────

local function nearDesk(player)
	local desk = AuctionService.desk
	if not desk then
		return true -- hub never built: don't lock anyone out of their own items
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - desk.Position).Magnitude <= Config.ShopRange
end

local function countListings(userId)
	local n = 0
	for _, lot in pairs(lots) do
		if lot.sellerId == userId then
			n += 1
		end
	end
	return n
end

--[[
	What a client is allowed to know about a lot. Everything, as it happens --
	an auction with hidden state isn't an auction.

	`endsAt` deliberately does NOT ship. It's an os.clock() value, and os.clock()
	has a different origin on every machine, so a client subtracting its own
	clock from the server's would get nonsense. Only the already-resolved
	`timeLeft` crosses the wire; the tick loop rebroadcasts every second so it
	stays honest, and the client just counts down between updates.
]]
local function publicLot(lot)
	local char = Brainrots.get(lot.item.charId)
	return {
		id = lot.id,
		charId = lot.item.charId,
		variantId = lot.item.variantId,
		name = Economy.displayName(lot.item.charId, lot.item.variantId),
		tier = char and char.tier or "Common",
		income = Economy.incomeOf(lot.item.charId, lot.item.variantId),
		sellerId = lot.sellerId,
		sellerName = lot.sellerName,
		floor = lot.floor,
		bid = lot.bid,
		bidderId = lot.bidderId, -- nil means the house is holding it
		bidderName = lot.bidderName,
		minNextBid = Auction.minNextBid(lot.bid),
		timeLeft = Auction.timeLeft(lot.endsAt),
	}
end

function AuctionService.snapshot()
	local list = {}
	for _, lot in pairs(lots) do
		table.insert(list, publicLot(lot))
	end
	-- Soonest to close first: that's the one worth looking at. Sorted on
	-- timeLeft because publicLot doesn't carry endsAt across the wire.
	table.sort(list, function(a, b)
		return a.timeLeft < b.timeLeft
	end)
	return list
end

local function broadcast()
	Net.get("AuctionState"):FireAllClients(AuctionService.snapshot())
end

--[[ Give a bidder their escrow back. Safe to call for the house (nil id) and
     for someone who has already left -- both are simply no-ops. ]]
local function refund(lot)
	if not lot.bidderId then
		return
	end
	local bidder = Players:GetPlayerByUserId(lot.bidderId)
	local profile = bidder and DataService.get(bidder)
	if profile then
		profile.money += lot.bid
		PlayerState.push(bidder)
		PlayerState.notify(bidder, "Outbid on " .. lot.name .. ". " ..
			Format.money(lot.bid) .. " refunded.", "info")
	end
end

-- ── listing ─────────────────────────────────────────────────────────────────

function AuctionService.list(player, uid)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if not nearDesk(player) then
		return { ok = false, err = "Use the consign desk in the Auction House." }
	end
	if countListings(player.UserId) >= Config.AuctionMaxListings then
		return { ok = false, err = "You already have " ..
			Config.AuctionMaxListings .. " lots on the block." }
	end

	local item, index = DataService.findItem(profile, uid)
	if not item then
		return { ok = false, err = "You don't own that." }
	end

	-- Out of the inventory entirely. It belongs to the lot now, which is what
	-- stops it earning rent and stops it being sold twice.
	table.remove(profile.inventory, index)

	local lot = {
		id = nextLotId,
		item = { uid = item.uid, charId = item.charId, variantId = item.variantId },
		name = Economy.displayName(item.charId, item.variantId),
		sellerId = player.UserId,
		sellerName = player.DisplayName,
		floor = Auction.floorPrice(item.charId, item.variantId),
		bidderId = nil,
		bidderName = nil,
		endsAt = os.clock() + Config.AuctionDuration,
	}
	lot.bid = lot.floor
	lots[lot.id] = lot
	nextLotId += 1

	-- It may have been sitting on a pad; refresh so the podium empties.
	PlotService.refresh(player)
	PlayerState.push(player)
	PlayerState.notify(player, lot.name .. " is on the block. House bid " ..
		Format.money(lot.floor) .. ".", "good")
	broadcast()

	return { ok = true, lot = publicLot(lot) }
end

-- ── bidding ─────────────────────────────────────────────────────────────────

function AuctionService.bid(player, lotId, amount)
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, err = "Still loading, one sec." }
	end
	if not nearDesk(player) then
		return { ok = false, err = "Bidding happens on the auction floor." }
	end

	local lot = lots[lotId]
	if not lot then
		return { ok = false, err = "That lot is gone." }
	end
	if lot.sellerId == player.UserId then
		return { ok = false, err = "You can't bid on your own lot." }
	end
	if lot.bidderId == player.UserId then
		return { ok = false, err = "You're already the top bid." }
	end

	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then
		return { ok = false, err = "Invalid bid." }
	end
	amount = math.floor(amount)

	local minimum = Auction.minNextBid(lot.bid)
	if amount < minimum then
		return { ok = false, err = "Bid at least " .. Format.money(minimum) .. "." }
	end
	if amount > profile.money then
		return { ok = false, err = "You can't afford that." }
	end

	-- Refund the player we're displacing BEFORE taking this one's money, so a
	-- player outbidding themselves across two lots can never be double-charged.
	refund(lot)

	profile.money -= amount
	lot.bid = amount
	lot.bidderId = player.UserId
	lot.bidderName = player.DisplayName

	-- Anti-snipe: a late bid buys everyone else another window to answer.
	local remaining = Auction.timeLeft(lot.endsAt)
	if remaining < Config.AuctionSnipeWindow then
		lot.endsAt = os.clock() + Config.AuctionSnipeWindow
	end

	PlayerState.push(player)
	broadcast()
	return { ok = true, lot = publicLot(lot) }
end

-- ── settlement ──────────────────────────────────────────────────────────────

--[[
	Close a lot and pay everyone out.

	The buyer's money was taken at bid time, so settlement only MOVES the item
	and pays the seller. The house buying (no bidder) mints the floor price --
	that's intended, it's the same money a pad would have paid out over the same
	15 minutes.
]]
local function settle(lot)
	lots[lot.id] = nil

	local seller = Players:GetPlayerByUserId(lot.sellerId)
	local sellerProfile = seller and DataService.get(seller)
	if sellerProfile then
		sellerProfile.money += lot.bid
		PlayerState.push(seller)
		PlayerState.notify(seller, lot.name .. " sold for " ..
			Format.money(lot.bid) ..
			(lot.bidderName and (" to " .. lot.bidderName) or " to the house") .. ".",
			"good")
	end

	if lot.bidderId then
		local buyer = Players:GetPlayerByUserId(lot.bidderId)
		local buyerProfile = buyer and DataService.get(buyer)
		if buyerProfile then
			table.insert(buyerProfile.inventory, {
				uid = DataService.nextUid(buyerProfile),
				charId = lot.item.charId,
				variantId = lot.item.variantId,
			})
			PlayerState.push(buyer)
			PlayerState.notify(buyer, "Won " .. lot.name .. " for " ..
				Format.money(lot.bid) .. ".", "good")
		else
			-- Buyer vanished between their last bid and the hammer. Their money
			-- is already spent and there's nobody to hand the item to; returning
			-- it to the seller who has also been paid would mint a duplicate.
			warn(("[Auction] buyer %d gone at settlement of lot %d")
				:format(lot.bidderId, lot.id))
		end
	end

	broadcast()
end

--[[ Hand the item back and refund the standing bidder. Used when the seller
     leaves -- nobody is paid, the lot simply never happened. ]]
local function cancel(lot, reason)
	lots[lot.id] = nil
	refund(lot)

	local seller = Players:GetPlayerByUserId(lot.sellerId)
	local profile = seller and DataService.get(seller)
	if profile then
		table.insert(profile.inventory, {
			uid = DataService.nextUid(profile),
			charId = lot.item.charId,
			variantId = lot.item.variantId,
		})
		PlayerState.push(seller)
		if reason then
			PlayerState.notify(seller, lot.name .. " came back: " .. reason, "info")
		end
	end
	broadcast()
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

function AuctionService.start()
	Net.get("ListBrainrot").OnServerInvoke = function(player, uid)
		return AuctionService.list(player, uid)
	end

	Net.get("PlaceBid").OnServerInvoke = function(player, lotId, amount)
		return AuctionService.bid(player, lotId, amount)
	end

	--[[
		Connected here rather than in Bootstrap so it runs BEFORE
		DataService.release: the returned item has to be in the profile at the
		moment it saves, or a disconnect during your own auction eats the
		brainrot.
	]]
	Players.PlayerRemoving:Connect(function(player)
		for _, lot in pairs(lots) do
			if lot.sellerId == player.UserId then
				cancel(lot, nil) -- seller is leaving; no notify to deliver
			elseif lot.bidderId == player.UserId then
				-- Refund and drop back to the house floor. Never below it, so a
				-- lot can't end up with a bid nobody is standing behind.
				refund(lot)
				lot.bid = lot.floor
				lot.bidderId = nil
				lot.bidderName = nil
			end
		end
		broadcast()
	end)

	-- The clock. One loop for every lot rather than a task.delay each, so a lot
	-- extended by an anti-snipe bid can't fire on its original deadline.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, lot in pairs(lots) do
				if now >= lot.endsAt then
					settle(lot)
				end
			end
			if next(lots) then
				broadcast() -- keeps every client's countdown honest
			end
		end
	end)

	game:BindToClose(function()
		for _, lot in pairs(lots) do
			settle(lot)
		end
	end)
end

return AuctionService

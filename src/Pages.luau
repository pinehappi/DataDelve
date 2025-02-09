-- Wrapper for page APIs
-- TBH this causes too much indirection, kind of annoying to use

local Pages = {}
Pages.__index = Pages

type PagesState = unknown
type PagesInterface = {
	initialize: () -> (PagesState?, string?),
	next: (PagesState) -> { items: { unknown }?, isFinished: boolean } | { error: string },
}
function Pages.new(interface: PagesInterface)
	local self = setmetatable({
		isFinished = false,
		pageNumber = 0,
		cache = {},

		interface = interface,

		_loadMoreListStyleState = nil,
	}, Pages)

	local state, err = interface.initialize()
	if err then
		return nil, err
	end

	self.state = state

	local _, err = self:increment()
	if err then
		return nil, err
	end
	return self
end

function Pages.wrapListing(callback: () -> DataStoreListingPages)
	return Pages.new({
		initialize = function()
			local success, result = pcall(callback)

			if not success then
				return nil, result
			end

			return { didFirst = false, pages = result }
		end,
		next = function(state: { didFirst: boolean, pages: DataStoreListingPages })
			if state.didFirst then
				local success, err = pcall(function()
					state.pages:AdvanceToNextPageAsync()
				end)
				if not success then
					return { error = err }
				else
					return { items = state.pages:GetCurrentPage(), isFinished = state.pages.IsFinished }
				end
			else
				state.didFirst = true
				return { items = state.pages:GetCurrentPage(), isFinished = state.pages.IsFinished }
			end
		end,
	} :: PagesInterface)
end

function Pages:get(pageNumber: number): ({ unknown }?, string?)
	if pageNumber < 1 then
		return nil, "Page number must be greater than 1."
	end
	if pageNumber == #self.cache + 1 then
		if self.isFinished then
			return nil, "Page number exceeds max page."
		end

		local result = self.interface.next(self.state)

		if result.error then
			return nil, result.error
		end

		self.isFinished = result.isFinished
		self.cache[pageNumber] = result.items

		return result.items
	elseif pageNumber > #self.cache then
		return nil, "Page number not loaded yet."
	end

	return
end

function Pages:getCurrent(): ({ unknown }?, string?)
	return self:get(self.pageNumber)
end

function Pages:increment(): ({ unknown }?, string?)
	local items, err = self:get(self.pageNumber + 1)
	if err then
		return nil, err
	else
		self.pageNumber += 1

		if self._loadMoreListStyleState then
			for _, item in items do
				self._loadMoreListStyleState:add(item)
			end
			self._loadMoreListStyleState:setLoadMoreVisible(not self.isFinished)
		end

		return items
	end
end

function Pages:isEmpty(): boolean
	return (#self.cache == 1) and (#self.cache[1] == 0) and self.isFinished
end

function Pages:syncWithLoadMoreListStyleState(styleState)
	self._loadMoreListStyleState = styleState
	for _, page in self.cache do
		for _, item in page do
			self._loadMoreListStyleState:add(item)
		end
	end

	self._loadMoreListStyleState:setLoadMoreVisible(not self.isFinished)
end

export type Pages = typeof(Pages.new({} :: any))

return Pages

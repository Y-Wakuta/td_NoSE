# rubocop:disable SingleSpaceBeforeFirstArg

NoSE::Schema.new do
  Workload 'rubis'

  Index 'users_by_region' do
    Hash    regions.id
    Ordered users.id
    Extra   users.nickname
    Path    regions.id, regions.users
  end

  Index 'user_data' do
    Hash    users.id
    Ordered regions.id
    Extra   users['*']
    Path    users.id
  end

  Index 'user_region' do
    Hash    users.id
    Ordered regions.id
    Extra   regions.name
    Path    users.id, users.region
  end

  Index 'user_buynow' do
    Hash    users.id
    Ordered buynow.date, buynow.id, items.id
    Extra   buynow.qty
    Path    users.id, users.bought_now, buynow.item
  end

  Index 'user_items_bid_on' do
    Hash    users.id
    Ordered bids.date, bids.id, items.id
    Extra   bids.qty
    Path    users.id, users.bids, bids.item
  end

  Index 'user_items_sold' do
    Hash    users.id
    Ordered bids.date, bids.id, items.id
    Path    users.id, users.items_sold, items.bids
  end

  Index 'user_comments_received' do
    Hash    users.id
    Ordered comments.id, items.id
    Extra   comments['*']
    Path    comments.id, comments.to_user
  end

  Index 'commenter' do
    Hash    comments.id
    Ordered users.id
    Extra   users.nickname
    Path    comments.id, comments.from_user
  end

  Index 'items_data' do
    Hash  items.id
    Extra items['*']
    Path  items.id
  end

  Index 'item_bids' do
    Hash    items.id
    Ordered bids.id, users.id
    Extra   items.max_bid, users.nickname, bids.qty, bids.bid, bids.date
    Path    items.id, items.bids, bids.user
  end

  Index 'items_by_category' do
    Hash    categories.id
    Ordered items.end_date, items.id
    Path    categories.id, categories.items
  end

  Index 'categories' do
    Hash    categories.dummy
    Ordered categories.id
    Extra   categories.name
    Path    categories.id
  end
end

# rubocop:enable SingleSpaceBeforeFirstArg

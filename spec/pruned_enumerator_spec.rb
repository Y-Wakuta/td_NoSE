module NoSE
  describe PrunedIndexEnumerator do
    include_context 'entities'
    include_context 'dummy cost model'
    subject(:pruned_enum) { PrunedIndexEnumerator.new workload, cost_model, 1, 100 }

    it 'produces a simple index for a filter' do
      query = Statement.parse 'SELECT User.Username FROM User ' \
                              'WHERE User.City = ?', workload.model
      indexes = pruned_enum.indexes_for_queries [query], []
      expect(indexes.to_a).to include \
        Index.new [user['City']], [user['UserId']], [user['Username']],
                  QueryGraph::Graph.from_path([user.id_field])
      expect(indexes.size).to be 5
    end

    it 'produces a simple index for a foreign key join' do
      query = Statement.parse 'SELECT Tweet.Body FROM Tweet.User ' \
                              'WHERE User.City = ?', workload.model
      indexes = pruned_enum.indexes_for_queries [query], []
      expect(indexes).to include \
        Index.new [user['City']], [user['UserId'], tweet['TweetId']],
                  [tweet['Body']],
                  QueryGraph::Graph.from_path([user.id_field,
                                               user['Tweets']])
      expect(indexes.size).to be 14
    end

    it 'produces an index for intermediate query steps' do
      query = Statement.parse 'SELECT Link.URL FROM Link.Tweets.User ' \
                              'WHERE User.Username = ?', workload.model
      indexes = pruned_enum.indexes_for_queries [query], []
      expect(indexes).to include \
        Index.new [user['UserId']], [tweet['TweetId']], [],
                  QueryGraph::Graph.from_path([tweet.id_field,
                                               tweet['User']])
      expect(indexes.size).to be 31
    end

    it 'produces a simple index for a filter within a workload' do
      query = Statement.parse 'SELECT User.Username FROM User ' \
                              'WHERE User.City = ?', workload.model
      workload.add_statement query
      indexes = pruned_enum.indexes_for_workload
      expect(indexes.to_a).to include \
        Index.new [user['City']], [user['UserId']], [user['Username']],
                  QueryGraph::Graph.from_path([user.id_field])
      expect(indexes.size).to be 5
    end

    it 'does not produce empty indexes' do
      query = Statement.parse 'SELECT Tweet.Body FROM Tweet.User ' \
                              'WHERE User.City = ?', workload.model
      workload.add_statement query
      indexes = pruned_enum.indexes_for_workload
      expect(indexes).to all(satisfy do |index|
        !index.order_fields.empty? || !index.extra.empty?
      end)
      expect(indexes.size).to be 12
    end

    it 'includes no indexes for updates if nothing is updated' do
      # Use a fresh workload for this test
      model = workload.model
      workload = Workload.new model
      pruned_enum = PrunedIndexEnumerator.new workload, cost_model, 1, 100
      update = Statement.parse 'UPDATE User SET Username = ? ' \
                               'WHERE User.City = ?', model
      workload.add_statement update
      indexes = pruned_enum.indexes_for_workload
      expect(indexes).to be_empty
    end

    it 'includes indexes enumerated from queries generated from updates' do
      # Use a fresh workload for this test
      model = workload.model
      workload = Workload.new model
      pruned_enum = PrunedIndexEnumerator.new workload, cost_model, 1, 100

      update = Statement.parse 'UPDATE User SET Username = ? ' \
                               'WHERE User.City = ?', model
      workload.add_statement update

      query = Statement.parse 'SELECT Tweet.Body FROM Tweet.User ' \
                              'WHERE User.Username = ?', workload.model
      workload.add_statement query

      indexes = pruned_enum.indexes_for_workload
      expect(indexes.to_a).to include \
        Index.new [user['City']], [user['UserId']], [],
                  QueryGraph::Graph.from_path([user.id_field])

      expect(indexes.to_a).to include \
        Index.new [user['UserId']], [tweet['TweetId']],
                  [tweet['Body']],
                  QueryGraph::Graph.from_path([user.id_field,
                                               user['Tweets']])
      expect(indexes.size).to be 19
    end

    it 'enumerates indexes for simple queries' do
      tpch_workload = Workload.new do |_|
        Model 'tpch'
        DefaultMix :default
        Group 'Group1', default: 1 do
          Q 'SELECT to_supplier.s_acctbal '\
            'FROM part.from_partsupp.to_supplier ' \
            'WHERE part.p_size = ?'

          Q 'SELECT lineitem.l_orderkey '\
            'FROM lineitem.to_orders.to_customer '\
            'WHERE to_customer.c_mktsegment = ?'\
        end
      end
      indexes = PrunedIndexEnumerator.new(tpch_workload, cost_model, 1, 100).indexes_for_workload.to_a
      expect(indexes.size).to be 41
    end

    it 'enumerates indexes for complicated queries and insert' do
      tpch_workload = Workload.new do |_|
        Model 'tpch'
        DefaultMix :default
        Group 'Group1', default: 1 do
          Q 'SELECT to_supplier.s_acctbal, to_supplier.s_name, to_nation.n_name, part.p_partkey, part.p_mfgr, '\
                'to_supplier.s_address, to_supplier.s_phone, to_supplier.s_comment ' \
                'FROM part.from_partsupp.to_supplier.to_nation.to_region ' \
                'WHERE part.p_size = ? AND part.p_type = ? AND from_partsupp.ps_supplycost = ? '\
                'ORDER BY to_supplier.s_acctbal, to_nation.n_name, to_supplier.s_name -- Q2_outer'

          Q 'SELECT lineitem.l_orderkey, sum(lineitem.l_extendedprice), sum(lineitem.l_discount), to_orders.o_orderdate, to_orders.o_shippriority '\
              'FROM lineitem.to_orders.to_customer '\
              'WHERE to_customer.c_mktsegment = ? AND to_orders.o_orderdate < ? AND lineitem.l_shipdate > ? '\
              'ORDER BY lineitem.l_extendedprice, lineitem.l_discount, to_orders.o_orderdate ' \
              'GROUP BY lineitem.l_orderkey, to_orders.o_orderdate, to_orders.o_shippriority -- Q3'

          Q 'INSERT INTO orders SET o_orderkey=?, o_orderstatus=?, o_totalprice=?, o_orderdate=?, o_orderpriority=?, '\
                        'o_clerk=?, o_shippriority=?, o_comment=? AND CONNECT TO to_customer(?) -- 4'
          Q 'INSERT INTO nation SET n_nationkey=?, n_name=?, n_comment=? AND CONNECT TO to_region(?) -- 5'
        end
      end
      indexes = PrunedIndexEnumerator.new(tpch_workload, cost_model, 1, 100).indexes_for_workload.to_a
      expect(indexes.size).to be 3859
    end
  end
end

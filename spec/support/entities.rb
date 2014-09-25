module Sadvisor
  RSpec.shared_examples 'entities' do
    let(:workload) do
      Workload.new do
        (Entity 'User' do
          ID     'UserId'
          String 'Username'
          String 'City'
        end) * 10

        Entity 'Link' do
          ID     'LinkId'
          String 'URL'
        end

        (Entity 'Tweet' do
          ID         'TweetId'
          String     'Body', 140, count: 5
          Integer    'Timestamp'
          ForeignKey 'User', 'User'
          ForeignKey 'Link', 'Link'
        end) * 1000
      end
    end
    let(:tweet) { workload['Tweet'] }
    let(:user) { workload['User'] }
    let(:link) { workload['Link'] }
    let(:query) {Statement.new 'SELECT URL FROM Link ' \
                               'WHERE Link.Tweet.User.Username = ?', workload }
  end
end

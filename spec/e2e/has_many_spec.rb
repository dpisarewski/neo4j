require 'spec_helper'

describe 'has_many' do
  let(:clazz_a) do
    UniqueClass.create do
      include Neo4j::ActiveNode
      property :name

      has_many :both, :friends, model_class: false
      has_many :out, :knows, model_class: self
      has_many :in, :knows_me, origin: :knows, model_class: self
    end
  end
  before { clazz_a }

  let(:node) { clazz_a.create }
  let(:friend1) { clazz_a.create }
  let(:friend2) { clazz_a.create }

  describe 'association?' do
    context 'with a present association' do
      subject { clazz_a.association?(:friends) }
      it { is_expected.to be_truthy }
    end

    context 'with a missing association' do
      subject { clazz_a.association?(:fooz) }
      it { is_expected.to be_falsey }
    end
  end

  describe 'associations_keys' do
    subject { clazz_a.associations_keys }
    it { is_expected.to include(:friends, :knows, :knows_me) }
  end

  describe 'non-persisted node' do
    let(:unsaved_node) { clazz_a.new }
    it 'returns an empty array' do
      expect(unsaved_node.friends).to eq []
    end

    it 'has a frozen array' do
      expect { unsaved_node.friends << friend1 }.to raise_error(RuntimeError)
    end
  end

  describe 'unique: true' do
    before { clazz_a.reflect_on_association(:knows).association.instance_variable_set(:@unique, true) }
    after do
      clazz_a.reflect_on_association(:knows).association.instance_variable_set(:@unique, false)
      [friend1, friend2].each(&:destroy)
    end

    it 'only creates one relationship between two nodes' do
      expect(friend1.knows.count).to eq 0
      friend1.knows << friend2
      expect(friend1.knows.count).to eq 1
      friend1.knows << friend2
      expect(friend1.knows.count).to eq 1
    end

    it 'is respected with an association using origin' do
      expect(friend1.knows.count).to eq 0
      friend2.knows_me << friend1
      expect(friend1.knows.count).to eq 1
      friend2.knows_me << friend1
      expect(friend1.knows.count).to eq 1
    end
  end

  describe 'rel_type' do
    it 'creates the correct type' do
      node.friends << friend1
      r = node.rel
      expect(r.rel_type).to eq(:'FRIENDS')
    end

    it 'creates the correct type' do
      node.knows << friend1
      r = node.rel
      expect(r.rel_type).to eq(:'KNOWS')
    end

    it 'creates correct incoming relationship' do
      node.knows_me << friend1
      expect(friend1.rel(dir: :outgoing).rel_type).to eq(:'KNOWS')
      expect(node.rel(dir: :incoming).rel_type).to eq(:'KNOWS')
    end
  end

  it 'access nodes via declared has_n method' do
    expect(node.friends.to_a).to eq([])
    expect(node.friends.any?).to be false

    node.friends << friend1
    expect(node.friends.to_a).to eq([friend1])
  end

  it 'access relationships via declared has_n method' do
    node.friends.rels.to_a.should eq([])
    node.friends << friend1
    rels = node.friends.rels
    rels.count.should eq(1)
    rel = rels.first
    rel.start_node.should eq(node)
    rel.end_node.should eq(friend1)
  end

  describe 'me.friends << friend_1 << friend' do
    it 'creates several relationships' do
      node.friends << friend1 << friend2
      node.friends.to_a.should =~ [friend1, friend2]
    end
  end

  describe 'me.friends = <array>' do
    it 'creates several relationships' do
      node.friends = [friend1, friend2]
      node.friends.to_a.should =~ [friend1, friend2]
    end

    context 'node with two friends' do
      before(:each) do
        node.friends = [friend1, friend2]
      end

      it 'is not empty' do
        expect(node.friends.any?).to be true
      end

      it 'removes relationships when given a different list' do
        friend3 = clazz_a.create
        node.friends = [friend3]
        node.friends.to_a.should =~ [friend3]
      end

      it 'removes relationships when given a partial list' do
        node.friends = [friend1]
        node.friends.to_a.should =~ [friend1]
      end

      it 'removes all relationships when given an empty list' do
        node.friends = []
        node.friends.to_a.should =~ []
      end

      it 'occurs within a transaction' do
        friend3 = clazz_a.create(name: 'foo')
        node.friends = [friend1, friend2]
        expect_any_instance_of(Neo4j::ActiveNode::Query::QueryProxy).to receive(:_create_relationship).and_raise
        expect { node.friends = [friend3] }.to raise_error
        expect(node.friends.to_a).to include(friend1, friend2)
        expect(node.friends.to_a).not_to include friend3
      end

      it 'can be accessed via [] operator' do
        expect([friend1, friend2]).to include(node.friends[0])
      end

      it 'has a to_s method' do
        expect(node.friends.to_s).to be_a(String)
      end

      it 'has a is_a method' do
        expect(node.friends.is_a?(Neo4j::ActiveNode::Query::QueryProxy)).to be true
        expect(node.friends.is_a?(Array)).to be false
        expect(node.friends.is_a?(String)).to be false
      end
    end
  end

  describe 'me.friends#create(other, since: 1994)' do
    describe 'creating relationships to existing nodes' do
      it 'creates a new relationship when given existing nodes and given properties' do
        node.friends.create(friend1, since: 1994)

        r = node.rel(dir: :outgoing, type: 'FRIENDS')

        r[:since].should eq(1994)
      end

      it 'creates new relationships when given an array of nodes and given properties' do
        node.friends.create([friend1, friend2], since: 1995)

        rs = node.rels(dir: :outgoing, type: 'FRIENDS')

        rs.map(&:end_node).should =~ [friend1, friend2]
        rs.each do |r|
          r[:since].should eq(1995)
        end
      end
    end

    describe 'creating relationships and nodes at the same time' do
      let(:node2) { double('unpersisted node', props: {name: 'Brad'}) }

      it 'creates a new relationship when given unpersisted node and given properties' do
        node.friends.create(clazz_a.new(name: 'Brad'), since: 1996)
        # node2.stub(:persisted?).and_return(false)
        # node2.stub(:save).and_return(true)
        # node2.stub(:neo_id).and_return(2)

        # node.friends.create(node2, since: 1996)
        r = node.rel(dir: :outgoing, type: 'FRIENDS')

        r[:since].should eq(1996)
        r.end_node.name.should eq('Brad')
      end

      it 'creates a new relationship when given an array of unpersisted nodes and given properties' do
        node.friends.create([clazz_a.new(name: 'James'), clazz_a.new(name: 'Cat')], since: 1997)

        rs = node.rels(dir: :outgoing, type: 'FRIENDS')

        rs.map(&:end_node).map(&:name).should =~ %w(James Cat)
        rs.each do |r|
          r[:since].should eq(1997)
        end
      end
    end
  end

  describe 'callbacks' do
    let(:clazz_c) do
      UniqueClass.create do
        include Neo4j::ActiveNode
        property :name

        has_many :out, :knows, model_class: self, before: :before_callback
        has_many :in, :knows_me, origin: :knows, model_class: self, after: :after_callback
        has_many :in, :will_fail, origin: :knows, model_class: self, before: :false_callback

        def before_callback(_other)
        end

        def after_callback(_other)
        end

        def false_callback(_other)
          false
        end
      end
    end

    let(:node) { clazz_a.create }
    let(:friend1) { clazz_a.create }
    let(:friend2) { clazz_a.create }

    let(:callback_friend1) { clazz_c.create }
    let(:callback_friend2) { clazz_c.create }

    it 'calls before_callback when node added to #knows association' do
      expect(callback_friend1).to receive(:before_callback).with(callback_friend2) { callback_friend1.knows.to_a.size.should eq(0) }
      callback_friend1.knows << callback_friend2
    end

    it 'calls after_callback when node added to #knows association' do
      expect(callback_friend1).to receive(:after_callback).with(callback_friend2) { callback_friend2.knows.to_a.size.should eq(1) }
      callback_friend1.knows_me << callback_friend2
    end

    it 'prevents the association from being created if before returns "false" explicitly' do
      callback_friend1.will_fail << callback_friend2
      expect(callback_friend1.knows_me.to_a.size).to eq 0
    end
  end

  describe 'model_class' do
    before(:each) do
      mc = model_class

      stub_active_node_class('Post') do
        has_many :in, :comments, type: :comments_on, model_class: mc
      end

      stub_active_node_class('Comment')

      stub_active_node_class('Person')
    end

    let!(:post) { Post.create }

    let!(:comments) { [Comment.create, Comment.create] }

    let!(:person) { Person.create }

    before(:each) do
      Neo4j::Session.query.match(post: :Post, comment: :Comment).where(comment: {uuid: comments.map(&:uuid)})
        .create('post<-[:comments_on]-comment').exec

      Neo4j::Session.query.match(post: :Post, person: :Person).where(person: {uuid: person.uuid})
        .create('post<-[:comments_on]-person').exec
    end

    subject { post.comments.pluck(:uuid).sort }
    context 'model_class: nil' do
      let(:model_class) { nil }
      # Should assume 'Comment' as the model from the association name
      it { should eq(comments.map(&:uuid).sort) }
    end

    context "model_class: 'Comment'" do
      let(:model_class) { 'Comment' }
      it { should eq(comments.map(&:uuid).sort) }
    end

    context "model_class: 'Person'" do
      let(:model_class) { 'Person' }
      it { should eq([person.uuid]) }
    end

    context 'model_class: false' do
      let(:model_class) { false }
      it { should eq((comments.map(&:uuid) + [person.uuid]).sort) }
    end

    context "model_class: ['Comment']" do
      let(:model_class) { ['Comment'] }
      it { should eq(comments.map(&:uuid).sort) }
    end

    context "model_class: ['Comment', 'Person']" do
      let(:model_class) { %w(Comment Person) }
      it { should eq((comments.map(&:uuid) + [person.uuid]).sort) }
    end
  end

  describe 'using mapped_label_name' do
    let(:clazz_c) do
      UniqueClass.create do
        include Neo4j::ActiveNode

        has_many :in, :furrs, model_class: 'ClazzD'
      end
    end

    let(:c1) { clazz_c.create }

    it 'should use the mapped_label_name' do
      clazz_d = UniqueClass.create do
        include Neo4j::ActiveNode

        self.mapped_label_name = 'Fuur'
      end

      stub_const 'ClazzD', clazz_d

      d1 = ClazzD.create

      c1.furrs << d1

      c1.furrs.to_a.should eq([d1])
    end
  end

  describe 'query chaining' do
    before(:each) do
      delete_db
      clear_model_memory_caches

      stub_active_node_class('Dog') do
        property :name

        has_many :out, :toys, type: :has_toy
      end
      stub_active_node_class('Toy') do
        property :name
      end
    end

    context 'one dog, two toys' do
      let!(:sparky) { Dog.create(name: 'Sparky') }
      let!(:spot) { Dog.create(name: 'Spot') }
      let!(:chewmate) { Toy.create(name: 'The Chew Mate') }
      let!(:realcat) { Toy.create(name: 'Real Cat') }

      context 'Sparky has both toys, Spot has just a Real Cat' do
        before(:each) do
          sparky.toys << chewmate
          sparky.toys << realcat

          spot.toys << realcat
        end

        it 'should return all toys for all dogs from Dog.toys' do
          expect(Dog.toys.to_a).to match_array([chewmate, realcat, realcat])
        end

        it 'should return all toys for all dogs specified by where' do
          expect(Dog.where(name: 'Sparky').toys.to_a).to match_array([chewmate, realcat])
          expect(Dog.where(name: 'Spot').toys.to_a).to match_array([realcat])
        end
      end
    end
  end

  describe 'transactions' do
    context 'failure' do
      it 'rolls back <<' do
        begin
          tx = Neo4j::Transaction.new
          node.friends << friend1
          tx.failure
        ensure
          tx.close
        end
        expect(node.friends.count).to eq 0
      end

      it 'rolls back =' do
        node.friends = friend1
        begin
          tx = Neo4j::Transaction.new
          node.friends = friend2
          tx.failure
        ensure
          tx.close
        end
        expect(node.friends.first).to eq friend1
      end
    end
  end
end

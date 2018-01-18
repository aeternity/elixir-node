defmodule Aecore.ChannelsPrototype.Channels do

  alias Aecore.Structures.ChannelTxData
  alias Aecore.Structures.MultisigTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Serialization
  alias Aehttpclient.Client

  require Logger

  def invite(peer_uri, amount, fee) do
    Client.send_channel_invite(peer_uri, amount, fee)
  end

  def accept_invite(peer_pubkey, amount) do
    pending_invites = Peers.pending_channel_invites()
    if(Map.has_key?(pending_invites, peer_pubkey)) do
      {:ok, own_pubkey} = Keys.pubkey()
      peer_uri = pending_invites[peer_pubkey].uri
      lock_amounts =
        %{own_pubkey => amount, peer_pubkey =>
                                pending_invites[peer_pubkey].lock_amount}
      fee = pending_invites[peer_pubkey].fee
      channel_tx_data = %ChannelTxData{lock_amounts: lock_amounts, fee: fee}
      {:ok, signature} = Keys.sign(channel_tx_data)
      signatures = %{own_pubkey => signature}
      serialized_multisig_tx =
        Serialization.tx(%MultisigTx{data: channel_tx_data,
                                     signatures: signatures}, :serialize)
      Client.accept_channel_invite(peer_uri, serialized_multisig_tx)
    else
      Logger.error(fn ->"No pending invite from #{peer_pubkey}" end)
    end
  end

  def make_channel_payment(address, amount) do
    channels = Peers.open_channels()
    if(Map.has_key?(channels, address) &&
       peer_has_channel_open_with_us(channels[address].uri)) do
      {:ok, own_pubkey} = Keys.pubkey()
      last_tx = get_last_valid_channel_tx(channels[address].txs)
      peer_address =
        Enum.find(Map.keys(last_tx.signatures), fn(address) -> address != own_pubkey end)
      new_tx_data =
        ChannelTxData.new(lock_amounts:
                            %{own_pubkey =>
                              last_tx.data.lock_amounts[own_pubkey] - amount,
                              peer_address =>
                              last_tx.data.lock_amounts[peer_address] + amount},
                          fee: last_tx.data.fee)
      {:ok, signature} = Keys.sign(new_tx_data)
      signatures = %{own_pubkey => signature}
      serialized_multisig_tx =
        Serialization.tx(%MultisigTx{data: new_tx_data,
                                     signatures: signatures}, :serialize)
      Client.send_channel_payment_tx(channels[address].uri, serialized_multisig_tx)
    else
      Logger.error(fn -> "No open channel with #{address}" end)
    end
  end

  def close_channel(address) do
    channels = Peers.open_channels()
    if(Map.has_key?(channels, address)) do
      channels[address].txs
      |> get_last_valid_channel_tx()
      |> Pool.add_transaction()
      Peers.close_channel(address)
    else
      Logger.error(fn -> "No open channel with #{address}" end)
    end
  end

  def accept_pending_tx(address) do
    channels = Peers.open_channels()
    pending_tx = channels[address].pending_tx
    {:ok, pubkey} = Keys.pubkey()
    {:ok, signature} = Keys.sign(pending_tx.data)
    updated_signatures = Map.put(pending_tx.signatures, pubkey, signature)
    serialized_multisig_tx =
      Serialization.tx(%MultisigTx{data: pending_tx.data,
                                   signatures: updated_signatures}, :serialize)
    Client.accept_channel_payment(channels[address].uri, serialized_multisig_tx)
    Peers.accept_pending_tx(address)
  end

  def get_last_valid_channel_tx(txs) do
    Enum.find(txs, fn(tx) -> Keys.verify_tx(tx) end)
  end

  def peer_has_channel_open_with_us(peer_uri) do
    {:ok, pubkey} = Keys.pubkey()
    open_channels = Client.get_open_channels(peer_uri)
    Enum.any?(open_channels, fn(address) -> address == pubkey end)
  end

  def check_open_channels() do
    Enum.each(Peers.open_channels(), fn{address, %{uri: uri}} ->
        if(!peer_has_channel_open_with_us(uri)) do
          Peers.close_channel(address)
        end
      end)
  end
end

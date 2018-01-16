defmodule Aecore.ChannelsPrototype.Channels do

  alias Aecore.Structures.ChannelTxData
  alias Aecore.Structures.MultisigTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Peers.Worker, as: Peers
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
end

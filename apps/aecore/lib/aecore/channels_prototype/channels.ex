defmodule Aecore.ChannelsPrototype.Channels do

  alias Aecore.Structures.ChannelTxData
  alias Aecore.Structures.MultisigTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Peers.Worker, as: Peers
  alias Aeutil.Serialization
  alias Aehttpclient.Client

  require Logger

  def invite(peer_uri, amount) do
    Client.send_channel_invite(peer_uri, amount)
  end

  def accept_invite(peer_uri, amount) do
    pending_invites = Peers.pending_channel_invites()
    if(Map.has_key?(pending_invites, peer_uri)) do
      {:ok, own_pubkey} = Keys.pubkey()
      case Client.get_info(peer_uri) do
        {:ok, info} ->
          peer_pubkey = Base.decode16!(info.public_key)
          lock_amounts =
            %{own_pubkey => amount, peer_pubkey => pending_invites[peer_uri]}
          channel_tx_data = %ChannelTxData{lock_amounts: lock_amounts}
          {:ok, signature} = Keys.sign(channel_tx_data)
          signatures = %{own_pubkey => signature}
          serialized_multisig_tx =
            Serialization.tx(%MultisigTx{data: channel_tx_data,
                                         signatures: signatures}, :serialize)
          Peers.remove_channel_invite(peer_uri)
          Client.accept_channel_invite(peer_uri, serialized_multisig_tx)
        {:error, message} ->
          Logger.error(fn ->
              "Couldn't get info from #{peer_uri} - #{message}"
            end)
      end
    else
      Logger.error(fn ->"No pending invite from #{peer_uri}" end)
    end
  end
end

defmodule Aecore.Tx.DataTx do
  @moduledoc """
  Module defining the Data transaction which encapsulates all of the different sub-transactions
  """
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Keys
  alias Aecore.Tx.DataTx
  alias Aeutil.{Bits, Serialization, TypeToTag}

  require Logger

  @typedoc "Name of the specified transaction module"
  @type tx_types ::
          Aecore.Account.Tx.SpendTx
          | Aecore.Oracle.Tx.OracleExtendTx
          | Aecore.Oracle.Tx.OracleRegistrationTx
          | Aecore.Oracle.Tx.OracleResponseTx
          | Aecore.Oracle.Tx.OracleResponseTx
          | Aecore.Naming.Tx.NamePreClaimTx
          | Aecore.Naming.Tx.NameClaimTx
          | Aecore.Naming.Tx.NameUpdateTx
          | Aecore.Naming.Tx.NameTransferTx
          | Aecore.Naming.Tx.NameRevokeTx
          | Aecore.Channel.Tx.ChannelCreateTx
          | Aecore.Channel.Tx.ChannelCloseMutalTx
          | Aecore.Channel.Tx.ChannelCloseSoloTx
          | Aecore.Channel.Tx.ChannelSlashTx
          | Aecore.Channel.Tx.ChannelSettleTx

  @typedoc "Structure of a transaction that may be added to the blockchain"
  @type payload ::
          Aecore.Account.Tx.SpendTx.t()
          | Aecore.Oracle.Tx.OracleExtendTx.t()
          | Aecore.Oracle.Tx.OracleRegistrationTx.t()
          | Aecore.Oracle.Tx.OracleResponseTx.t()
          | Aecore.Oracle.Tx.OracleResponseTx.t()
          | Aecore.Naming.Tx.NamePreClaimTx.t()
          | Aecore.Naming.Tx.NameClaimTx.t()
          | Aecore.Naming.Tx.NameUpdateTx.t()
          | Aecore.Naming.Tx.NameTransferTx.t()
          | Aecore.Naming.Tx.NameRevokeTx.t()
          | Aecore.Channel.Tx.ChannelCreateTx.t()
          | Aecore.Channel.Tx.ChannelCloseMutalTx.t()
          | Aecore.Channel.Tx.ChannelCloseSoloTx.t()
          | Aecore.Channel.Tx.ChannelSlashTx.t()
          | Aecore.Channel.Tx.ChannelSettleTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the main transaction wrapper"
  @type t :: %DataTx{
          type: tx_types(),
          payload: payload(),
          senders: list(binary()),
          fee: non_neg_integer(),
          nonce: non_neg_integer(),
          ttl: non_neg_integer()
        }

  @nonce_size 256

  @doc """
  Definition of the DataTx structure

  # Parameters
  - type: The type of transaction that may be added to the blockchain
  - payload: The strcuture of the specified transaction type
  - senders: The public addresses of the accounts originating the transaction. First element of this list is special - it's the main sender. Nonce is applied to main sender Account.
  - fee: The amount of tokens given to the miner
  - nonce: An integer bigger then current nonce of main sender Account. (see senders)
  """
  defstruct [:type, :payload, :senders, :fee, :nonce, :ttl]
  use ExConstructor

  def valid_types do
    [
      Aecore.Account.Tx.SpendTx,
      Aecore.Oracle.Tx.OracleExtendTx,
      Aecore.Oracle.Tx.OracleQueryTx,
      Aecore.Oracle.Tx.OracleRegistrationTx,
      Aecore.Oracle.Tx.OracleResponseTx,
      Aecore.Naming.Tx.NameClaimTx,
      Aecore.Naming.Tx.NamePreClaimTx,
      Aecore.Naming.Tx.NameRevokeTx,
      Aecore.Naming.Tx.NameTransferTx,
      Aecore.Naming.Tx.NameUpdateTx,
      Aecore.Channel.Tx.ChannelCreateTx,
      Aecore.Channel.Tx.ChannelCloseSoloTx,
      Aecore.Channel.Tx.ChannelCloseMutalTx,
      Aecore.Channel.Tx.ChannelSlashTx,
      Aecore.Channel.Tx.ChannelSettleTx
    ]
  end

  def nonce_size, do: @nonce_size

  @spec init(
          tx_types(),
          map(),
          list(binary()) | binary(),
          non_neg_integer(),
          integer(),
          non_neg_integer()
        ) :: DataTx.t()
  def init(type, payload, senders, fee, nonce, ttl \\ 0) do
    if is_list(senders) do
      identified_senders =
        for sender <- senders do
          case sender do
            %Identifier{} ->
              sender

            address ->
              Identifier.create_identity(address, :account)
          end
        end

      %DataTx{
        type: type,
        payload: type.init(payload),
        senders: identified_senders,
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }
    else
      sender = Identifier.create_identity(senders, :account)

      %DataTx{
        type: type,
        payload: type.init(payload),
        senders: [sender],
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }
    end
  end

  @spec init_binary(tx_types(), map(), list(binary()), binary(), binary(), binary()) ::
          {:ok, DataTx.t()} | {:error, String.t()}
  def init_binary(type, payload, encoded_senders, fee, nonce, ttl) do
    with {:ok, senders} <- Identifier.decode_list_from_binary(encoded_senders) do
      {:ok,
       %DataTx{
         type: type,
         payload: type.init(payload),
         senders: senders,
         fee: fee,
         nonce: nonce,
         ttl: ttl
       }}
    else
      {:error, _} = error -> error
    end
  end

  @spec senders(DataTx.t(), Chainstate.t()) :: list(binary())
  def senders(%DataTx{senders: senders, type: type, payload: payload} = tx, chainstate) do
    if chainstate_senders?(tx) do
      type.senders_from_chainstate(payload, chainstate)
    else
      for sender <- senders do
        sender.value
      end
    end
  end

  @spec main_sender(DataTx.t(), Chainstate.t()) :: binary() | nil
  def main_sender(tx, chainstate) do
    List.first(senders(tx, chainstate))
  end

  @spec ttl(DataTx.t()) :: non_neg_integer()
  def ttl(%DataTx{ttl: ttl}) do
    case ttl do
      0 -> :max_ttl
      ttl -> ttl
    end
  end

  @spec chainstate_senders?(DataTx.t()) :: boolean()
  def chainstate_senders?(%DataTx{type: type}) do
    type.chainstate_senders?()
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%DataTx{fee: fee, type: type, senders: senders} = tx) do
    cond do
      !Enum.member?(valid_types(), type) ->
        {:error, "#{__MODULE__}: Invalid tx type=#{type}"}

      fee < 0 ->
        {:error, "#{__MODULE__}: Negative fee"}

      !senders_pubkeys_size_valid?(senders) ->
        {:error, "#{__MODULE__}: Invalid senders pubkey size"}

      DataTx.ttl(tx) < 0 ->
        {:error,
         "#{__MODULE__}: Invalid TTL value: #{DataTx.ttl(tx)} can't be a negative integer."}

      true ->
        payload_validate(tx)
    end
  end

  @doc """
  Changes the chainstate (account state and tx_type_state) according
  to the given transaction requirements
  """
  @spec process_chainstate(Chainstate.t(), non_neg_integer(), DataTx.t()) ::
          {:ok, Chainstate.t()} | {:error, String.t()}
  def process_chainstate(chainstate, block_height, %DataTx{payload: payload, fee: fee} = tx) do
    accounts_state = chainstate.accounts

    tx_type_state = Map.get(chainstate, tx.type.get_chain_state_name(), %{})

    nonce_accounts_state =
      AccountStateTree.update(accounts_state, main_sender(tx, chainstate), fn acc ->
        Account.apply_nonce!(acc, tx.nonce)
      end)

    processed_states =
      nonce_accounts_state
      |> tx.type.deduct_fee(block_height, payload, tx, fee)
      |> tx.type.process_chainstate(
        tx_type_state,
        block_height,
        payload,
        tx
      )

    case processed_states do
      {:ok, {new_accounts_state, new_tx_type_state}} ->
        new_chainstate =
          if tx.type.get_chain_state_name() == :accounts do
            %{chainstate | accounts: new_accounts_state}
          else
            %{chainstate | accounts: new_accounts_state}
            |> Map.put(tx.type.get_chain_state_name(), new_tx_type_state)
          end

        {:ok, new_chainstate}

      error ->
        error
    end
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(Chainstate.t(), non_neg_integer(), DataTx.t()) ::
          :ok | {:error, String.t()}
  def preprocess_check(chainstate, block_height, %DataTx{payload: payload, type: type} = tx) do
    accounts_state = chainstate.accounts
    tx_type_state = Map.get(chainstate, type.get_chain_state_name(), %{})

    tx_type_preprocess_check =
      type.preprocess_check(accounts_state, tx_type_state, block_height, payload, tx)

    cond do
      tx_type_preprocess_check != :ok ->
        tx_type_preprocess_check

      DataTx.ttl(tx) < block_height ->
        {:error,
         "#{__MODULE__}: Invalid or expired TTL value: #{DataTx.ttl(tx)}, with given block's height: #{
           block_height
         }"}

      Account.nonce(chainstate.accounts, main_sender(tx, chainstate)) >= tx.nonce ->
        {:error, "#{__MODULE__}: Transaction nonce too small #{tx.nonce}"}

      true ->
        :ok
    end
  end

  @spec serialize(map()) :: map()
  def serialize(%DataTx{} = tx) do
    map_without_senders = %{
      "type" => Serialization.serialize_value(tx.type),
      "payload" => Serialization.serialize_value(tx.payload),
      "fee" => Serialization.serialize_value(tx.fee),
      "nonce" => Serialization.serialize_value(tx.nonce),
      "ttl" => Serialization.serialize_value(tx.ttl)
    }

    if length(tx.senders) == 1 do
      [%Identifier{value: sender}] = tx.senders

      Map.put(
        map_without_senders,
        "sender",
        Serialization.serialize_value(sender, :sender)
      )
    else
      new_senders = for %Identifier{value: sender} <- tx.senders, do: sender

      Map.put(
        map_without_senders,
        "senders",
        Serialization.serialize_value(new_senders, :senders)
      )
    end
  end

  @spec deserialize(map()) :: DataTx.t()
  def deserialize(%{sender: sender} = data_tx) do
    init(data_tx.type, data_tx.payload, [sender], data_tx.fee, data_tx.nonce, data_tx.ttl)
  end

  def deserialize(%{senders: senders} = data_tx) do
    init(data_tx.type, data_tx.payload, senders, data_tx.fee, data_tx.nonce, data_tx.ttl)
  end

  @spec base58c_encode(binary()) :: String.t()
  def base58c_encode(bin) do
    Bits.encode58c("th", bin)
  end

  @spec base58c_decode(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode(<<"th$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec standard_deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def standard_deduct_fee(
        accounts,
        block_height,
        %DataTx{senders: [%Identifier{value: sender} | _]},
        fee
      ) do
    AccountStateTree.update(accounts, sender, fn acc ->
      Account.apply_transfer!(acc, block_height, fee * -1)
    end)
  end

  defp payload_validate(%DataTx{type: type, payload: payload} = data_tx) do
    type.validate(payload, data_tx)
  end

  defp senders_pubkeys_size_valid?([sender | rest]) do
    if Keys.key_size_valid?(sender) do
      senders_pubkeys_size_valid?(rest)
    else
      false
    end
  end

  defp senders_pubkeys_size_valid?([]) do
    true
  end

  @spec encode_to_list(DataTx.t()) :: list()
  def encode_to_list(%DataTx{} = tx) do
    {:ok, tag} = TypeToTag.type_to_tag(tx.type)
    [tag | tx.type.encode_to_list(tx.payload, tx)]
  end

  @spec rlp_encode(DataTx.t()) :: binary()
  def rlp_encode(%DataTx{} = tx) do
    tx
    |> encode_to_list()
    |> ExRLP.encode()
  end

  @spec rlp_decode(binary()) :: {:ok, DataTx.t()} | {:error, String.t()}
  def rlp_decode(binary) do
    case Serialization.rlp_decode_anything(binary) do
      {:ok, %DataTx{}} = result ->
        result

      {:ok, _} ->
        {:error, "#{__MODULE__}: Invalid type"}

      {:error, _} = error ->
        error
    end
  end
end

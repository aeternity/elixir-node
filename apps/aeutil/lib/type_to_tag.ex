defmodule Aeutil.TypeToTag do
  @moduledoc """
  Conversion from structure types to numeric tags for RLP encoding end reverse.
  """

  @spec tag_to_type(non_neg_integer()) :: {:ok, atom()} | {:error, String.t()}
  def tag_to_type(10), do: {:ok, Aecore.Account.Account}
  def tag_to_type(11), do: {:ok, Aecore.Tx.SignedTx}
  def tag_to_type(12), do: {:ok, Aecore.Account.Tx.SpendTx}
  def tag_to_type(20), do: {:ok, Aecore.Oracle.Oracle}
  def tag_to_type(21), do: {:ok, Aecore.Oracle.OracleQuery}
  def tag_to_type(22), do: {:ok, Aecore.Oracle.Tx.OracleRegistrationTx}
  def tag_to_type(23), do: {:ok, Aecore.Oracle.Tx.OracleQueryTx}
  def tag_to_type(24), do: {:ok, Aecore.Oracle.Tx.OracleResponseTx}
  def tag_to_type(25), do: {:ok, Aecore.Oracle.Tx.OracleExtendTx}
  def tag_to_type(30), do: {:ok, Aecore.Naming.NameClaim}
  def tag_to_type(31), do: {:ok, Aecore.Naming.NameCommitment}
  def tag_to_type(32), do: {:ok, Aecore.Naming.Tx.NameClaimTx}
  def tag_to_type(33), do: {:ok, Aecore.Naming.Tx.NamePreClaimTx}
  def tag_to_type(34), do: {:ok, Aecore.Naming.Tx.NameUpdateTx}
  def tag_to_type(35), do: {:ok, Aecore.Naming.Tx.NameRevokeTx}
  def tag_to_type(36), do: {:ok, Aecore.Naming.Tx.NameTransferTx}
  # Contract - 40
  # Contract call - 41
  # Contract create transaction - 42
  # Contract call transaction - 43
  def tag_to_type(50), do: {:ok, Aecore.Channel.Tx.ChannelCreateTx}
  # Channel deposit transaction - 51
  # Channel withdraw transaction - 52
  def tag_to_type(53), do: {:ok, Aecore.Channel.Tx.ChannelCloseMutalTx}
  def tag_to_type(54), do: {:ok, Aecore.Channel.Tx.ChannelCloseSoloTx}
  def tag_to_type(55), do: {:ok, Aecore.Channel.Tx.ChannelSlashTx}
  def tag_to_type(57), do: {:ok, Aecore.Channel.Tx.ChannelSettleTx}
  def tag_to_type(58), do: {:ok, Aecore.Channel.ChannelStateOnChain}
  def tag_to_type(59), do: {:ok, Aecore.Channel.Tx.ChannelSnapshotSoloTx}
  # POI - 60
  # Non Epoch tags:
  def tag_to_type(100), do: {:ok, Aecore.Chain.Block}
  def tag_to_type(101), do: {:ok, Aecore.Channel.ChannelStateOffChain}
  # ChannelStateOffChain signing_form 102
  def tag_to_type(tag), do: {:error, "#{__MODULE__}: Unknown tag: #{inspect(tag)}"}

  @spec type_to_tag(atom()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def type_to_tag(Aecore.Account.Account), do: {:ok, 10}
  def type_to_tag(Aecore.Tx.SignedTx), do: {:ok, 11}
  def type_to_tag(Aecore.Account.Tx.SpendTx), do: {:ok, 12}
  def type_to_tag(Aecore.Oracle.Oracle), do: {:ok, 20}
  def type_to_tag(Aecore.Oracle.OracleQuery), do: {:ok, 21}
  def type_to_tag(Aecore.Oracle.Tx.OracleRegistrationTx), do: {:ok, 22}
  def type_to_tag(Aecore.Oracle.Tx.OracleQueryTx), do: {:ok, 23}
  def type_to_tag(Aecore.Oracle.Tx.OracleResponseTx), do: {:ok, 24}
  def type_to_tag(Aecore.Oracle.Tx.OracleExtendTx), do: {:ok, 25}
  def type_to_tag(Aecore.Naming.NameClaim), do: {:ok, 30}
  def type_to_tag(Aecore.Naming.NameCommitment), do: {:ok, 31}
  def type_to_tag(Aecore.Naming.Tx.NameClaimTx), do: {:ok, 32}
  def type_to_tag(Aecore.Naming.Tx.NamePreClaimTx), do: {:ok, 33}
  def type_to_tag(Aecore.Naming.Tx.NameUpdateTx), do: {:ok, 34}
  def type_to_tag(Aecore.Naming.Tx.NameRevokeTx), do: {:ok, 35}
  def type_to_tag(Aecore.Naming.Tx.NameTransferTx), do: {:ok, 36}
  # Contract - 40
  # Contract call - 41
  # Contract create transaction - 42
  # Contract call transaction - 43
  def type_to_tag(Aecore.Channel.Tx.ChannelCreateTx), do: {:ok, 50}
  # Channel deposit transaction - 51
  # Channel withdraw transaction - 52
  def type_to_tag(Aecore.Channel.Tx.ChannelCloseMutalTx), do: {:ok, 53}
  def type_to_tag(Aecore.Channel.Tx.ChannelCloseSoloTx), do: {:ok, 54}
  def type_to_tag(Aecore.Channel.Tx.ChannelSlashTx), do: {:ok, 55}
  def type_to_tag(Aecore.Channel.Tx.ChannelSettleTx), do: {:ok, 57}
  def type_to_tag(Aecore.Channel.ChannelStateOnChain), do: {:ok, 58}
  def type_to_tag(Aecore.Channel.Tx.ChannelSnapshotSoloTx), do: {:ok, 59}
  # POI - 60
  # Non Epoch tags
  def type_to_tag(Aecore.Chain.Block), do: {:ok, 100}
  def type_to_tag(Aecore.Channel.ChannelStateOffChain), do: {:ok, 101}
  # ChannelStateOffChain signing_form 102
  def type_to_tag(type), do: {:error, "#{__MODULE__}: Non serializable type: #{type}"}
end

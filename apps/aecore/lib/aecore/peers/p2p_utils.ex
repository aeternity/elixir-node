defmodule Aecore.Peers.P2PUtils do
  @noise_timeout 5000

  def ranch_child_spec(pool_name, acceptors, port, module, state) do
    :ranch.child_spec(
      pool_name,
      acceptors,
      :ranch_tcp,
      [port: port],
      module,
      state
    )
  end

  def noise_opts(privkey, pubkey, r_pubkey, genesis_hash, version) do
    [
      {:rs, :enoise_keypair.new(:dh25519, r_pubkey)}
      | noise_opts(privkey, pubkey, genesis_hash, version)
    ]
  end

  def noise_opts(privkey, pubkey, genesis_hash, version) do
    [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, privkey, pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
  end

  def noise_opts do
    [noise: "Noise_NN_25519_ChaChaPoly_BLAKE2b"]
  end
end

defmodule Onestack.PasswordHasher do
  @default_algorithm :bcrypt
  @default_bcrypt_log_rounds 12
  @default_argon2id_params %{
    t_cost: 3,
    m_cost: 15,
    parallelism: 2,
    hash_len: 32,
    argon2_type: 2
  }

  def hash_password(password, algorithm \\ @default_algorithm)

  def hash_password(password, :bcrypt) do
    hash_password(password, :bcrypt, @default_bcrypt_log_rounds)
  end

  def hash_password(password, :pkbdf2) do
    Pbkdf2.hash_pwd_salt(password, digest: :sha256, format: :django, rounds: 600_000)
  end

  def hash_password(password, :argon2id) do
    salt = :crypto.strong_rand_bytes(16)

    hash_hex =
      Argon2.Base.hash_password(password, salt,
        t_cost: @default_argon2id_params.t_cost,
        m_cost: @default_argon2id_params.m_cost,
        parallelism: @default_argon2id_params.parallelism,
        hashlen: @default_argon2id_params.hash_len,
        argon2_type: @default_argon2id_params.argon2_type,
        format: :raw_hash
      )

    salt_hex = Base.encode16(salt, case: :lower)

    formatted_output =
      "argon2id$#{salt_hex}$#{memory_cost_from_exponent()}$#{@default_argon2id_params.t_cost}$#{@default_argon2id_params.parallelism}$#{hash_hex}"

    {formatted_output, salt_hex}
  end

  def hash_password(password, :bcrypt, log_rounds) do
    salt = Bcrypt.Base.gen_salt(log_rounds)
    hash = Bcrypt.Base.hash_password(password, salt)
    {hash, salt}
  end

  defp memory_cost_from_exponent do
    trunc(:math.pow(2, @default_argon2id_params.m_cost))
  end
end

defmodule Onestack.MemberManager do
  use GenServer
  require Logger
  alias Onestack.InvitationEmail

  @ets_table :member_results

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(@ets_table, [:set, :public, :named_table])
    {:ok, %{}}
  end

  def add_member(email, products) do
    job_id = generate_job_id()
    GenServer.cast(__MODULE__, {:add_member, email, products, job_id})
    _email = InvitationEmail.send_invitation(email, job_id)
    {:ok, job_id}
  end

  def remove_member(email, products) do
    job_id = generate_job_id()
    GenServer.cast(__MODULE__, {:remove_member, email, products, job_id})
    {:ok, job_id}
  end

  def handle_cast({:add_member, email, products, job_id}, state) do
    Task.start(fn ->
      Task.async_stream(
        products,
        fn product ->
          password = generate_password()
          {hashed_password, salt} = hash_password(password)
          result = add_member_to_product(email, password, hashed_password, salt, product)
          :ets.insert(@ets_table, {{job_id, product}, result})
          result
        end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Stream.run()
    end)

    {:noreply, state}
  end

  def handle_cast({:remove_member, email, products, job_id}, state) do
    Task.start(fn ->
      Task.async_stream(
        products,
        fn product ->
          result = remove_member_from_product(email, product)
          :ets.insert(@ets_table, {{job_id, product}, result})
          result
        end,
        max_concurrency: 5
      )
      |> Stream.run()
    end)

    {:noreply, state}
  end

  # Product-specific add member functions
  defp add_member_to_product(email, password, hashed_password, _salt, "cal") do
    {:ok, pid} = Postgrex.start_link(get_db_config("cal"))

    name = extract_name_from_email(email)
    email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

    user_query = """
    INSERT INTO "users" (name, email, "emailVerified")
    VALUES ($1, $2, $3)
    RETURNING id
    """

    user_params = [name, email, email_verified]

    case Postgrex.query(pid, user_query, user_params) do
      {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
        IO.puts("User inserted successfully in cal with ID: #{db_user_id}")

        password_query = """
        INSERT INTO "UserPassword" ("userId", hash)
        VALUES ($1, $2)
        """

        password_params = [db_user_id, hashed_password]

        case Postgrex.query(pid, password_query, password_params) do
          {:ok, _result} ->
            IO.puts("Password inserted successfully for cal")
            IO.puts("Generated Password for #{email}: #{password}")

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to insert password for cal: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to insert user for cal: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  defp add_member_to_product(email, password, hashed_password, _salt, "formbricks" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    result =
      Postgrex.transaction(pid, fn conn ->
        name = extract_name_from_email(email)
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        # Insert User
        user_insert_query = """
        INSERT INTO "User" (id, created_at, updated_at, name, email, password, email_verified)
        VALUES ($1, $2, $2, $3, $4, $5, $6)
        RETURNING id
        """

        user_id = Cuid2.create()

        {:ok, %{rows: [[^user_id]]}} =
          Postgrex.query(
            conn,
            user_insert_query,
            [user_id, email_verified, name, email, hashed_password, email_verified]
          )

        # Create an organization
        org_insert_query = """
        INSERT INTO "Organization" (id, created_at, updated_at, name, billing)
        VALUES ($1, $2, $2, $3, $4)
        RETURNING id
        """

        org_name = "#{name}'s Organization"
        billing = "{}"
        org_id = Cuid2.create()

        {:ok, %{rows: [[^org_id]]}} =
          Postgrex.query(
            conn,
            org_insert_query,
            [org_id, email_verified, org_name, billing]
          )

        # Create membership
        membership_insert_query = """
        INSERT INTO "Membership" ("userId", "organizationId", accepted, role)
        VALUES ($1, $2, $3, $4)
        """

        Postgrex.query!(conn, membership_insert_query, [user_id, org_id, true, "owner"])

        # Create a product
        product_insert_query = """
        INSERT INTO "Product" (id, created_at, updated_at, name, "organizationId")
        VALUES ($1, $2, $2, $3, $4)
        RETURNING id
        """

        product_name = "My Product"
        product_id = Cuid2.create()

        {:ok, %{rows: [[^product_id]]}} =
          Postgrex.query(
            conn,
            product_insert_query,
            [product_id, email_verified, product_name, org_id]
          )

        # Create environments
        env_insert_query = """
        INSERT INTO "Environment" (id, created_at, updated_at, type, "productId")
        VALUES ($1, $2, $2, $3, $4)
        """

        Postgrex.query!(conn, env_insert_query, [
          Cuid2.create(),
          email_verified,
          "production",
          product_id
        ])

        Postgrex.query!(conn, env_insert_query, [
          Cuid2.create(),
          email_verified,
          "development",
          product_id
        ])

        {user_id, org_id, product_id}
      end)

    case result do
      {:ok, {_user_id, _org_id, product_id}} ->
        IO.puts("#{product_name} user registration complete!")
        IO.puts("Generated Password for #{email}: #{password}")

      {:error, error} ->
        IO.puts("Failed to complete #{product_name} operations: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  defp add_member_to_product(email, password, hashed_password, salt, "nocodb") do
    {:ok, pid} = Postgrex.start_link(get_db_config("nocodb"))

    nocodb_id = generate_random_string()
    base_id = generate_random_string()
    notification_id = generate_random_string()

    user_query = """
    INSERT INTO "nc_users_v2" (id, email, password, salt)
    VALUES ($1, $2, $3, $4)
    """

    user_params = [
      nocodb_id,
      email,
      hashed_password,
      salt
    ]

    base_query = """
    INSERT INTO "nc_bases_v2" (id, title, meta, deleted, is_meta, "order")
    VALUES ($1, $2, $3, $4, $5, $6)
    """

    meta_json = Jason.encode!(%{"iconColor" => "#36BFFF"})

    base_params = [
      base_id,
      "Getting Started",
      meta_json,
      false,
      true,
      1
    ]

    relationship_query = """
    INSERT INTO "nc_base_users_v2" (base_id, fk_user_id, roles)
    VALUES ($1, $2, $3)
    """

    relationship_params = [
      base_id,
      nocodb_id,
      "owner"
    ]

    notification_query = """
    INSERT INTO "notification" (id, type, body, is_read, is_deleted, fk_user_id)
    VALUES ($1, $2, $3, $4, $5, $6)
    """

    notification_params = [
      notification_id,
      "app.welcome",
      "{}",
      false,
      false,
      nocodb_id
    ]

    case Postgrex.query(pid, user_query, user_params) do
      {:ok, _result} ->
        IO.puts("User inserted successfully in nocodb")
        IO.puts("Generated Password for #{email}: #{password}")

        case Postgrex.query(pid, base_query, base_params) do
          {:ok, _result} ->
            IO.puts("Base created successfully in nocodb")

            case Postgrex.query(pid, relationship_query, relationship_params) do
              {:ok, _result} ->
                IO.puts("Relationship created successfully in nocodb")

                case Postgrex.query(pid, notification_query, notification_params) do
                  {:ok, _result} ->
                    IO.puts("Notification created successfully in nocodb")

                  {:error, %Postgrex.Error{} = error} ->
                    IO.puts("Failed to create notification in nocodb: #{inspect(error)}")
                end

              {:error, %Postgrex.Error{} = error} ->
                IO.puts("Failed to create relationship in nocodb: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to create base in nocodb: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to insert user in nocodb: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  defp add_member_to_product(email, password, hashed_password, _salt, "n8n" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config("n8n"))

    result =
      Postgrex.transaction(pid, fn conn ->
        # Check if user exists
        check_user_query = """
        SELECT id, disabled FROM "user" WHERE email = $1
        """

        case Postgrex.query(conn, check_user_query, [email]) do
          {:ok, %Postgrex.Result{num_rows: 1, rows: [[existing_user_id, disabled]]}} ->
            if disabled do
              # User exists but is disabled, enable them
              update_query = """
              UPDATE "user" SET disabled = false WHERE id = $1
              """

              {:ok, _} = Postgrex.query(conn, update_query, [existing_user_id])
              {:existing_enabled, existing_user_id}
            else
              # User already exists and is not disabled
              {:existing_active, existing_user_id}
            end

          {:ok, %Postgrex.Result{num_rows: 0}} ->
            # User doesn't exist, create new user
            user_query = """
            INSERT INTO "user" (email, password, role, disabled)
            VALUES ($1, $2, $3, $4)
            RETURNING id
            """

            user_params = [email, hashed_password, "global:member", false]

            {:ok, %Postgrex.Result{rows: [[user_id]]}} =
              Postgrex.query(conn, user_query, user_params)

            # Insert project
            project_id = Ecto.UUID.generate()

            project_query = """
            INSERT INTO "project" (id, name, type)
            VALUES ($1, $2, $3)
            """

            project_params = [project_id, email, "personal"]

            {:ok, _} = Postgrex.query(conn, project_query, project_params)

            # Insert project relation
            relation_query = """
            INSERT INTO "project_relation" ("projectId", "userId", role)
            VALUES ($1, $2, $3)
            """

            relation_params = [project_id, user_id, "project:personalOwner"]

            {:ok, _} = Postgrex.query(conn, relation_query, relation_params)

            {:new_user, user_id, project_id}

          {:error, error} ->
            {:error, error}
        end
      end)

    case result do
      {:ok, {:existing_enabled, user_id}} ->
        IO.puts("Existing user re-enabled in #{product_name} with ID: #{inspect(user_id)}")

      {:ok, {:existing_active, user_id}} ->
        IO.puts(
          "User already exists and is active in #{product_name} with ID: #{inspect(user_id)}"
        )

      {:ok, {:new_user, user_id, project_id}} ->
        IO.puts("New user inserted successfully in #{product_name} with ID: #{inspect(user_id)}")
        IO.puts("Generated Password for #{email}: #{password}")
        IO.puts("Hashed Password: #{hashed_password}")
        IO.puts("Role: global:admin")

        IO.puts(
          "Project inserted successfully in #{product_name} with ID: #{inspect(project_id)}"
        )

        IO.puts("Project relation inserted successfully in #{product_name}")

      {:error, error} ->
        IO.puts("Failed to complete #{product_name} operations: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  defp add_member_to_product(email, password, hashed_password, _salt, "castopod" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))

    email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

    insert_user_query = """
    INSERT INTO cp_users (username)
    VALUES (?)
    RETURNING id
    """

    case MyXQL.query(conn, insert_user_query, [email]) do
      {:ok, %MyXQL.Result{rows: [[castopod_user_id]]}} ->
        IO.puts("User inserted successfully in castopod with ID: #{castopod_user_id}")

        insert_auth_identity_query = """
        INSERT INTO cp_auth_identities (user_id, secret2, secret, type)
        VALUES (?, ?, ?, ?)
        """

        case MyXQL.query(conn, insert_auth_identity_query, [
               castopod_user_id,
               hashed_password,
               email,
               "email_password"
             ]) do
          {:ok, _} ->
            IO.puts("Authentication identity added successfully for #{product_name}")

            insert_auth_group_query = """
            INSERT INTO cp_auth_groups_users (user_id, `group`, created_at)
            VALUES (?, ?, ?)
            """

            case MyXQL.query(conn, insert_auth_group_query, [
                   castopod_user_id,
                   "manager",
                   email_verified
                 ]) do
              {:ok, _} ->
                IO.puts("User group added successfully for #{product_name}")
                IO.puts("Generated Password for #{email}: #{password}")

              {:error, error} ->
                IO.puts("Failed to add user group for #{product_name}: #{inspect(error)}")
            end

          {:error, error} ->
            IO.puts(
              "Failed to add authentication identity for #{product_name}: #{inspect(error)}"
            )
        end

      {:error, error} ->
        IO.puts("Failed to insert user for #{product_name}: #{inspect(error)}")
    end

    %{email: email, password: password}
  end

  defp remove_member_from_product(email, "n8n" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    query = """
    UPDATE "user"
    SET disabled = true
    WHERE email = $1
    """

    params = [email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        IO.puts("User disabled successfully in #{product_name} for email: #{email}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to disable user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  defp remove_member_from_product(email, "nocodb" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    query = """
    DELETE FROM "nc_users_v2"
    WHERE email = $1
    """

    params = [email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} when num_rows > 0 ->
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  defp remove_member_from_product(email, "castopod") do
    {:ok, conn} = MyXQL.start_link(get_db_config("castopod"))

    # First, get the user ID
    get_user_id_query = "SELECT id FROM cp_users WHERE username = ?"

    case MyXQL.query(conn, get_user_id_query, [email]) do
      {:ok, %MyXQL.Result{rows: [[user_id]]}} ->
        # Delete from cp_auth_groups_users table
        delete_group_query = "DELETE FROM cp_auth_groups_users WHERE user_id = ?"
        MyXQL.query!(conn, delete_group_query, [user_id])

        # Delete from cp_auth_identities table
        delete_identity_query = "DELETE FROM cp_auth_identities WHERE user_id = ?"
        MyXQL.query!(conn, delete_identity_query, [user_id])

        # Delete from cp_users table
        delete_user_query = "DELETE FROM cp_users WHERE id = ?"
        MyXQL.query!(conn, delete_user_query, [user_id])

        IO.puts("User removed successfully from castopod")

      {:ok, %MyXQL.Result{rows: []}} ->
        IO.puts("No user found with email #{email} in castopod")

      {:error, error} ->
        IO.puts("Error querying user in castopod: #{inspect(error)}")
    end
  end

  defp remove_member_from_product(email, "cal" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # First, get the user ID
    user_query = "SELECT id FROM users WHERE email = $1"
    user_params = [email]

    case Postgrex.query(pid, user_query, user_params) do
      {:ok, %Postgrex.Result{rows: [[user_id]]}} ->
        # Delete from UserPassword table
        password_query = "DELETE FROM \"UserPassword\" WHERE \"userId\" = $1"
        password_params = [user_id]

        case Postgrex.query(pid, password_query, password_params) do
          {:ok, _result} ->
            IO.puts("Password removed for cal user")

            # Delete from users table
            delete_query = "DELETE FROM users WHERE id = $1"
            delete_params = [user_id]

            case Postgrex.query(pid, delete_query, delete_params) do
              {:ok, _result} ->
                IO.puts("User removed from cal")

              {:error, %Postgrex.Error{} = error} ->
                IO.puts("Failed to remove user from cal: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to remove password for cal user: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        IO.puts("User not found in cal")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error querying user in cal: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  defp remove_member_from_product(email, "formbricks" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    query = """
    DELETE FROM "User"
    WHERE email = $1
    """

    params = [email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} when num_rows > 0 ->
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  # Helper function to extract name from email
  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(".", " ")
    |> String.capitalize()
  end

  defp get_db_config(product_name) do
    Application.get_env(:onestack, :products)
    |> Enum.find(&(&1.name == product_name))
    |> Map.get(:db_config)
  end

  def generate_random_string(length \\ 20) when length > 0 do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> binary_part(0, length)
  end

  def generate_password(length \\ 30) when length >= 12 do
    symbols = ~c"!@#$%^&*()_+-=[]{}|;:,.<>?"

    alphanumeric = Enum.concat([?A..?Z, ?a..?z, ?0..?9])

    base =
      Stream.repeatedly(fn -> Enum.random(alphanumeric ++ symbols) end)
      |> Enum.take(length - 4)

    required = [
      Enum.random(?A..?Z),
      Enum.random(?a..?z),
      Enum.random(?0..?9),
      Enum.random(symbols)
    ]

    (base ++ required)
    |> Enum.shuffle()
    |> List.to_string()
  end

  def hash_password(password, log_rounds \\ 12) do
    salt = Bcrypt.Base.gen_salt(log_rounds)
    hash = Bcrypt.Base.hash_password(password, salt)
    {hash, salt}
  end

  def get_job_results(job_id, clear \\ false) do
    results =
      :ets.match_object(@ets_table, {{job_id, :_}, :_})
      |> Enum.map(fn {{^job_id, product}, result} -> {product, result} end)
      |> Enum.into(%{})

    if clear do
      :ets.match_delete(@ets_table, {{job_id, :_}, :_})
    end

    results
  end

  defp generate_job_id, do: UUID.uuid4()

  defp generate_invitation_url(job_id) do
    # Generate URL for your invitation LiveView, including the job_id
    "http://onestack.cloud/invitations/#{job_id}"
  end

  def invite_member(inviter, invitee_email, products) do
    with {:ok, job_id} <- MemberManager.add_member(invitee_email, products),
         {:ok, invitation} <- Accounts.create_invitation(inviter, invitee_email, job_id) do
      # Generate invitation URL
      invitation_url = generate_invitation_url(job_id)

      # Send email with invitation URL
      Onestack.Mailer.deliver_invitation_email(invitee_email, invitation_url)

      {:ok, invitation}
    else
      error -> error
    end
  end

  def send_invitation_email(inviter, invitee_email, job_id) do
    # Create invitation
    {:ok, invitation} = Accounts.create_invitation(inviter, invitee_email)

    # Generate invitation URL
    invitation_url = generate_invitation_url(job_id)

    # Send email with invitation URL
    Onestack.Mailer.deliver_invitation_email(invitee_email, invitation_url)
  end
end

defmodule Onestack.MemberManager do
  use GenServer
  # Services retired from the host (docs/adr/0006 and 0007). Plane was retired on
  # 27 September 2026.
  @retired_products ~w(chatwoot kimai librechat penpot plane twenty)

  require Logger

  alias Onestack.{
    InvitationEmail,
    MatrixAccounts,
    Repo,
    Accounts
  }

  require Logger
  import Ecto.Query

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
    lowercase_products = Enum.map(products, &String.downcase/1)
    GenServer.cast(__MODULE__, {:add_member, email, lowercase_products, job_id})
    {:ok, job_id}
  end

  def remove_member(email, products) do
    job_id = generate_job_id()
    lowercase_products = Enum.map(products, &String.downcase/1)
    GenServer.cast(__MODULE__, {:remove_member, email, lowercase_products, job_id})
    {:ok, job_id}
  end

  def handle_cast({:add_member, email, products, job_id}, state) do
    _results =
      Enum.map(products, fn product ->
        add_member_to_product(email, product)
      end)

    # if Enum.all?(results, &is_map/1) do
    #   InvitationEmail.send_invitation(email, job_id)
    # else
    #   Logger.error("Failed to add member to all products for email: #{email}")
    # end

    {:noreply, state}
  end

  def handle_cast({:remove_member, email, products, job_id}, state) do
    Enum.each(products, fn product ->
      result = remove_member_from_product(email, product)
      :ets.insert(@ets_table, {{job_id, product}, result})
    end)

    {:noreply, state}
  end

  # Retired products are skipped so teams that still list them do not break
  # provisioning, removal or password changes.
  def add_member_to_product(_email, product_name) when product_name in @retired_products do
    Logger.info("Skipping retired product #{product_name}")
    {:ok, {:skipped, :retired}}
  end

  def add_member_to_product(email, "matrix") do
    # TODO: check if email is already in DB and if so just reset the password
    # Check if the email exists in MatrixAccounts
    # TODO: Enter password directly in DB

    case Onestack.MatrixAccounts.list_users() |> Enum.find(&(&1.email == email)) do
      nil ->
        # Email not found, proceed with registration
        registration_token = System.get_env("MATRIX_REGISTRATION_TOKEN", "")
        url = System.get_env("MATRIX_API_URL", "https://matrix.localhost") <> "/_matrix/client/v3/register"

        body =
          Jason.encode!(%{
            email: email,
            # password: password,
            initial_device_display_name: "Onestack Auto Registration",
            auth: %{
              type: "m.login.registration_token",
              token: registration_token
            }
          })

        case HTTPoison.post(url, body) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            Logger.info("User created successfully in Matrix")

            # Parse the response body
            case Jason.decode(response_body) do
              {:ok, decoded_response} ->
                user_id =
                  decoded_response["user_id"]

                # Insert user_id and email into matrix_users table
                MatrixAccounts.create_matrix_user(%{email: email, matrix_id: user_id})

              {:error, _} ->
                Logger.error("Failed to parse response body")
            end

          {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
            Logger.error("Failed to create user in Matrix. Status code: #{status_code}")
            Logger.error("Response: #{response_body}")

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("Error creating user in Matrix: #{inspect(reason)}")
        end

      existing_user ->
        # Email found, update the existing user
        url = System.get_env("N8N_MATRIX_RESET_URL", "https://n8n.localhost/webhook/matrix/reset_password")

        headers = [
          {"Content-Type", "application/json"},
          {"onestack_matrix", System.get_env("MATRIX_WEBHOOK_SECRET", "")}
        ]

        body = Jason.encode!(%{matrix_id: existing_user.matrix_id})

        # Build and send the request
        request = Finch.build(:post, url, headers, body)

        case Finch.request(request, Onestack.Finch) do
          {:ok, response} ->
            Logger.info("Response status: #{response.status}")
            Logger.info("Response body: #{response.body}")

          {:error, reason} ->
            Logger.error("Error: #{inspect(reason)}")
        end

        Onestack.MatrixAccounts.update_matrix_user(existing_user, %{active: true})
        # %{email: existing_user.matrix_id, password: password}
        Logger.info("Existing user reactivated in Matrix")
    end
  end

  # Product-specific add member functions
  def add_member_to_product(email, "cal" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    # Check if the email exists with @onestack.cloud suffix
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    check_query = """
    SELECT id, email FROM users
    WHERE email LIKE $1
    """

    email_pattern =
      if String.ends_with?(email, "@onestack.cloud") do
        # For emails already ending in @onestack.cloud
        "#{email}%"
      else
        # For regular emails
        "#{email}@onestack.cloud%"
      end

    case Postgrex.query(pid, check_query, [email_pattern]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_email_query = """
        UPDATE users SET email = $1 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_email_query, [email, user_id]) do
          {:ok, _} ->
            password_query = """
            UPDATE "UserPassword" SET hash = $1 WHERE "userId" = $2
            """

            password_params = [hashed_password, user_id]

            case Postgrex.query(pid, password_query, password_params) do
              {:ok, _result} ->
                Logger.info(
                  "User reactivated successfully in #{product_name} with ID: #{user_id}"
                )

              {:error, %Postgrex.Error{} = error} ->
                Logger.error("Failed to insert password for #{product_name}: #{inspect(error)}")
            end

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        # User not found, proceed with new user creation
        name = extract_name_from_email(email)
        {:ok, uuid_binary} = Ecto.UUID.dump(Ecto.UUID.generate())
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        user_query = """
        INSERT INTO "users" (uuid, name, email, "emailVerified")
        VALUES ($1, $2, $3, $4)
        RETURNING id
        """

        user_params = [uuid_binary, name, email, email_verified]

        case Postgrex.query(pid, user_query, user_params) do
          {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
            password_query = """
            INSERT INTO "UserPassword" ("userId", hash)
            VALUES ($1, $2)
            """

            password_params = [db_user_id, hashed_password]

            case Postgrex.query(pid, password_query, password_params) do
              {:ok, _result} ->
                Logger.info(
                  "User inserted successfully in #{product_name} with ID: #{db_user_id}"
                )

              {:error, %Postgrex.Error{} = error} ->
                Logger.error("Failed to insert password for #{product_name}: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            Logger.error("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def add_member_to_product(email, "formbricks" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    try do
      # Check if the email exists with @onestack.cloud suffix
      check_query = """
      SELECT id, email FROM "User"
      WHERE email LIKE $1
      """

      email_pattern =
        if String.ends_with?(email, "@onestack.cloud") do
          # For emails already ending in @onestack.cloud
          "#{email}%"
        else
          # For regular emails
          "#{email}@onestack.cloud%"
        end

      case Postgrex.query(pid, check_query, [email_pattern]) do
        {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
          # User found, reactivate by removing @onestack.cloud and random string
          reactivate_query = """
          UPDATE "User" SET email = $1 WHERE id = $2
          """

          case Postgrex.query(pid, reactivate_query, [email, user_id]) do
            {:ok, _} ->
              Logger.info("User reactivated successfully in formbricks")

            {:error, error} ->
              Logger.error("Failed to reactivate user in formbricks: #{inspect(error)}")
          end

        {:ok, %Postgrex.Result{rows: []}} ->
          # User not found, proceed with new user creation
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
            {:ok, {_user_id, _org_id, _product_id}} ->
              Logger.info("#{product_name} user registration complete!")

            {:error, error} ->
              Logger.error("Failed to complete #{product_name} operations: #{inspect(error)}")
          end

        {:error, %Postgrex.Error{} = error} ->
          Logger.error("Error checking for existing user in formbricks: #{inspect(error)}")
      end
    after
      GenServer.stop(pid)
    end
  end

  def add_member_to_product(email, "nocodb" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash
    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT email FROM "nc_users_v2"
    WHERE email LIKE $1
    """

    email_pattern =
      if String.ends_with?(email, "@onestack.cloud") do
        # For emails already ending in @onestack.cloud
        "#{email}%"
      else
        # For regular emails
        "#{email}@onestack.cloud%"
      end

    case Postgrex.query!(pid, check_query, [email_pattern]) do
      %Postgrex.Result{num_rows: 1, rows: [[disabled_email]]} ->
        # Email found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE "nc_users_v2"
        SET email = $1
        WHERE email = $2
        """

        Postgrex.query!(pid, reactivate_query, [email, disabled_email])

      {:ok, %Postgrex.Result{rows: []}} ->
        # Email not found, proceed with new user creation
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
          hashed_password
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
            Logger.info("User inserted successfully in nocodb")

            case Postgrex.query(pid, base_query, base_params) do
              {:ok, _result} ->
                Logger.info("Base created successfully in nocodb")

                case Postgrex.query(pid, relationship_query, relationship_params) do
                  {:ok, _result} ->
                    Logger.info("Relationship created successfully in nocodb")

                    case Postgrex.query(pid, notification_query, notification_params) do
                      {:ok, _result} ->
                        Logger.info("Notification created successfully in nocodb")

                      {:error, %Postgrex.Error{} = error} ->
                        Logger.error("Failed to create notification in nocodb: #{inspect(error)}")
                    end

                  {:error, %Postgrex.Error{} = error} ->
                    Logger.error("Failed to create relationship in nocodb: #{inspect(error)}")
                end

              {:error, %Postgrex.Error{} = error} ->
                Logger.error("Failed to create base in nocodb: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            Logger.error("Failed to insert user in nocodb: #{inspect(error)}")
        end
    end

    GenServer.stop(pid)
  end

  def add_member_to_product(email, "n8n" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config("n8n"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

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
        Logger.info("Existing user re-enabled in #{product_name} with ID: #{inspect(user_id)}")

      {:ok, {:existing_active, user_id}} ->
        Logger.info(
          "User already exists and is active in #{product_name} with ID: #{inspect(user_id)}"
        )

      {:ok, {:new_user, user_id, project_id}} ->
        Logger.info(
          "New user inserted successfully in #{product_name} with ID: #{inspect(user_id)}"
        )

        Logger.info("Hashed Password: #{hashed_password}")
        Logger.info("Role: global:admin")

        Logger.info(
          "Project inserted successfully in #{product_name} with ID: #{inspect(project_id)}"
        )

        Logger.info("Project relation inserted successfully in #{product_name}")

      {:error, error} ->
        Logger.error("Failed to complete #{product_name} operations: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def add_member_to_product(email, "castopod" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash
    # Check if the email exists with @onestack.cloud suffix
    check_query =
      "SELECT id, username FROM cp_users WHERE username LIKE ?"

    email_pattern =
      if String.ends_with?(email, "@onestack.cloud") do
        # For emails already ending in @onestack.cloud
        "#{email}%"
      else
        # For regular emails
        "#{email}@onestack.cloud%"
      end

    case MyXQL.query(conn, check_query, [email_pattern]) do
      {:ok, %MyXQL.Result{rows: [[castopod_user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = "UPDATE cp_users SET username = ? WHERE id = ?"

        case MyXQL.query(conn, reactivate_query, [email, castopod_user_id]) do
          {:ok, _} ->
            insert_auth_identity_query = """
            UPDATE cp_auth_identities SET secret2 = ? WHERE user_id = ?
            """

            case MyXQL.query(conn, insert_auth_identity_query, [
                   hashed_password,
                   castopod_user_id
                 ]) do
              {:ok, _} ->
                Logger.info("Authentication identity added successfully for #{product_name}")

              {:error, error} ->
                Logger.error("Failed to reactivate user in castopod: #{inspect(error)}")
            end

            Logger.info("User reactivated successfully in castopod")

          {:error, error} ->
            Logger.error("Failed to reactivate user in castopod: #{inspect(error)}")
        end

      {:ok, %MyXQL.Result{rows: []}} ->
        # User not found, proceed with new user creation
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        insert_user_query = """
        INSERT INTO cp_users (username)
        VALUES (?)
        RETURNING id
        """

        case MyXQL.query(conn, insert_user_query, [email]) do
          {:ok, %MyXQL.Result{rows: [[castopod_user_id]]}} ->
            Logger.info("User inserted successfully in castopod with ID: #{castopod_user_id}")

            # Insert password for user
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
                Logger.info("Authentication identity added successfully for #{product_name}")

                # Create a "Manager" auth group for user so that they can create/edit podcasts
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
                    Logger.info("User group added successfully for #{product_name}")

                  {:error, error} ->
                    Logger.error(
                      "Failed to add user group for #{product_name}: #{inspect(error)}"
                    )
                end

              {:error, error} ->
                Logger.error(
                  "Failed to add authentication identity for #{product_name}: #{inspect(error)}"
                )
            end

          {:error, error} ->
            Logger.error("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, error} ->
        Logger.error("Error checking for existing user in castopod: #{inspect(error)}")
    end
  end

  def add_member_to_product(email, "documenso" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash
    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT id, email FROM "User"
    WHERE email LIKE $1
    """

    email_pattern =
      if String.ends_with?(email, "@onestack.cloud") do
        # For emails already ending in @onestack.cloud
        "#{email}%"
      else
        # For regular emails
        "#{email}@onestack.cloud%"
      end

    case Postgrex.query(pid, check_query, [email_pattern]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE "User" SET email = $1, password = $3 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_query, [email, user_id, hashed_password]) do
          {:ok, _} ->
            Logger.info("User reactivated successfully in #{product_name}")

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        # User not found, proceed with new user creation
        name = extract_name_from_email(email)
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        user_query = """
        INSERT INTO "User" (name, email, "emailVerified", password, "identityProvider", roles)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id
        """

        user_params = [name, email, email_verified, hashed_password, "DOCUMENSO", ["USER"]]

        case Postgrex.query(pid, user_query, user_params) do
          {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
            Logger.info("User inserted successfully in #{product_name} with ID: #{db_user_id}")

          {:error, %Postgrex.Error{} = error} ->
            Logger.error("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  # Retired products are skipped so teams that still list them do not break
  # provisioning, removal or password changes.
  def remove_member_from_product(_email, product_name) when product_name in @retired_products do
    Logger.info("Skipping retired product #{product_name}")
    {:ok, {:skipped, :retired}}
  end

  def remove_member_from_product(email, "cal" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # First, get the user ID
    user_query = "SELECT id FROM users WHERE email = $1"
    user_params = [email]

    case Postgrex.query(pid, user_query, user_params) do
      {:ok, %Postgrex.Result{rows: [[user_id]]}} ->
        # Update UserPassword table to set hash to null
        password_query = "UPDATE \"UserPassword\" SET hash = '' WHERE \"userId\" = $1"

        case Postgrex.query(pid, password_query, [user_id]) do
          {:ok, _result} ->
            Logger.info("Password removed for #{product_name} user")

          {:error, %Postgrex.Error{} = error} ->
            Logger.error("Failed to remove password for #{product_name} user: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        Logger.info("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error querying user in #{product_name}: #{inspect(error)}")
    end

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    query = """
    UPDATE "users"
    SET email = $1
    WHERE email = $2
    """

    params = [new_email, email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} when num_rows > 0 ->
        Logger.info("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def remove_member_from_product(email, "n8n" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    query = """
    UPDATE "user"
    SET disabled = true
    WHERE email = $1
    """

    params = [email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Logger.info("User disabled successfully in #{product_name} for email: #{email}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Failed to disable user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def remove_member_from_product(email, "nocodb" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    query = """
    UPDATE "nc_users_v2"
    SET email = $1
    WHERE email = $2
    """

    params = [new_email, email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} when num_rows > 0 ->
        Logger.info("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def remove_member_from_product(email, "castopod" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    # Update the user's email
    update_query = "UPDATE cp_users SET username = ? WHERE username = ?"

    case MyXQL.query(conn, update_query, [new_email, email]) do
      {:ok, %MyXQL.Result{num_rows: 1}} ->
        Logger.info("User deactivated successfully in castopod")

      {:ok, %MyXQL.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in castopod")

      {:error, error} ->
        Logger.error("Error updating user in castopod: #{inspect(error)}")
    end
  end

  def remove_member_from_product(email, "formbricks" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    query = """
    UPDATE "User"
    SET email = $1
    WHERE email = $2
    """

    params = [new_email, email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Logger.info("User deactivated successfully in #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Failed to update user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def remove_member_from_product(email, "matrix" = _product_name) do
    {:ok, updated_user} = MatrixAccounts.update_matrix_user_by_email(email, %{active: false})
    url = System.get_env("N8N_MATRIX_DEACTIVATE_URL", "https://n8n.localhost/webhook/matrix/deactivate")

    headers = [
      {"Content-Type", "application/json"},
      {"onestack_matrix", System.get_env("MATRIX_WEBHOOK_SECRET", "")}
    ]

    body = Jason.encode!(%{matrix_id: updated_user.matrix_id})

    # Build and send the request
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Onestack.Finch) do
      {:ok, response} ->
        Logger.info("Response status: #{response.status}")
        Logger.info("Response body: #{response.body}")

      {:error, reason} ->
        Logger.error("Error: #{inspect(reason)}")
    end
  end

  def remove_member_from_product(email, "documenso" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # First, get the user ID
    user_query = "SELECT id FROM \"User\" WHERE email = $1"
    user_params = [email]

    case Postgrex.query(pid, user_query, user_params) do
      {:ok, %Postgrex.Result{rows: [[user_id]]}} ->
        # Update UserPassword table to set hash to null
        password_query = "UPDATE \"User\" SET password = '' WHERE id = $1"

        case Postgrex.query(pid, password_query, [user_id]) do
          {:ok, _result} ->
            Logger.info("Password removed for #{product_name} user")

          {:error, %Postgrex.Error{} = error} ->
            Logger.error("Failed to remove password for #{product_name} user: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        Logger.info("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error querying user in #{product_name}: #{inspect(error)}")
    end

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    query = """
    UPDATE "User"
    SET email = $1
    WHERE email = $2
    """

    params = [new_email, email]

    case Postgrex.query(pid, query, params) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} when num_rows > 0 ->
        Logger.info("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  # Retired products are skipped so teams that still list them do not break
  # provisioning, removal or password changes.
  def update_password_for_product(_email, product_name) when product_name in @retired_products do
    Logger.info("Skipping retired product #{product_name}")
    {:ok, {:skipped, :retired}}
  end

  def update_password_for_product(_email, "matrix") do
  end

  def update_password_for_product(email, "cal") do
    {:ok, pid} = Postgrex.start_link(get_db_config("cal"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE "UserPassword"
    SET hash = $1
    WHERE "userId" IN (SELECT id FROM users WHERE email = $2)
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for cal user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error("Failed to update password for cal user: #{email}. Error: #{inspect(error)}")
        GenServer.stop(pid)
        {:error, error}
    end
  end

  def update_password_for_product(email, "formbricks") do
    {:ok, pid} = Postgrex.start_link(get_db_config("formbricks"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE "User" SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for formbricks user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for formbricks user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(pid)
        {:error, error}
    end
  end

  def update_password_for_product(email, "nocodb") do
    {:ok, pid} = Postgrex.start_link(get_db_config("nocodb"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE "nc_users_v2" SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for nocodb user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for nocodb user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(pid)
        {:error, error}
    end
  end

  def update_password_for_product(email, "n8n") do
    {:ok, pid} = Postgrex.start_link(get_db_config("n8n"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE "user" SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for n8n user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error("Failed to update password for n8n user: #{email}. Error: #{inspect(error)}")
        GenServer.stop(pid)
        {:error, error}
    end
  end

  def update_password_for_product(email, "castopod") do
    {:ok, conn} = MyXQL.start_link(get_db_config("castopod"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE cp_auth_identities SET secret2 = ?
    WHERE user_id IN (SELECT id FROM cp_users WHERE username = ?)
    """

    case MyXQL.query(conn, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for castopod user: #{email}")
        GenServer.stop(conn)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for castopod user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(conn)
        {:error, error}
    end
  end

  def update_password_for_product(email, "documenso") do
    {:ok, pid} = Postgrex.start_link(get_db_config("documenso"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE "User" SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for documenso user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for documenso user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(pid)
        {:error, error}
    end
  end

  # Helper function to extract name from email
  def extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(".", " ")
    |> String.capitalize()
  end

  def get_db_config(product_name) do
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

  # Add this new function to handle the delayed deletion

  def generate_job_id, do: UUID.uuid4()
end

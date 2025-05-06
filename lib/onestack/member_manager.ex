defmodule Onestack.MemberManager do
  use GenServer
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

  def add_member_to_product(email, "matrix") do
    # TODO: check if email is already in DB and if so just reset the password
    # Check if the email exists in MatrixAccounts
    # TODO: Enter password directly in DB

    case Onestack.MatrixAccounts.list_users() |> Enum.find(&(&1.email == email)) do
      nil ->
        # Email not found, proceed with registration
        registration_token = System.get_env("CONDUIT_REGISTRATION_TOKEN")
        url = "https://matrix.#{System.get_env("PHX_HOST")}/_matrix/client/v3/register"

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

      _existing_user ->
        # Email found, update the existing user
        #TODO: Activate the user and update password



        # Onestack.MatrixAccounts.update_matrix_user(existing_user, %{active: true})
        # %{email: existing_user.matrix_id, password: password}
        Logger.info("Existing user detected. No action taken in Matrix")
    end
  end

  def add_member_to_product(email, "chatwoot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    # Check if the email exists with @onestack.cloud suffix
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    check_query = """
    SELECT id, email FROM users
    WHERE email LIKE $1
    """

    # Handle both cases: emails already ending with @onestack.cloud and those that don't
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
        UPDATE users SET email = $1, encrypted_password = $2 WHERE id = $3
        """

        case Postgrex.query(pid, reactivate_email_query, [email, hashed_password, user_id]) do
          {:ok, _} ->
            Logger.info("User reactivated successfully in #{product_name} with ID: #{user_id}")

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        # User not found, proceed with new user creation
        name = extract_name_from_email(email)
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        # 1. Create new user
        user_query = """
        INSERT INTO users (provider, uid, encrypted_password, confirmed_at, created_at, updated_at, name, email)
        VALUES ($1, $2, $3, $4, $4, $4, $5, $2)
        RETURNING id
        """

        user_params = ["email", email, hashed_password, email_verified, name]

        case Postgrex.query(pid, user_query, user_params) do
          {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
            token_query = """
            INSERT INTO access_tokens (owner_type, owner_id, token, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $4)
            """

            token_params = [
              "User",
              db_user_id,
              :crypto.strong_rand_bytes(24) |> Base.url_encode64() |> binary_part(0, 24),
              email_verified
            ]

            case Postgrex.query(pid, token_query, token_params) do
              {:ok, _result} ->
                Logger.info(
                  "User inserted successfully in #{product_name} with ID: #{db_user_id}"
                )

                # 2. Create new account
                account_creation_query = """
                INSERT INTO accounts (name, created_at, updated_at, feature_flags)
                VALUES ($1, $2, $2, $3)
                RETURNING id
                """

                account_name =
                  :crypto.strong_rand_bytes(18) |> Base.url_encode64() |> binary_part(0, 18)

                account_creation_params = [account_name, email_verified, 33_029_775]

                case Postgrex.query(pid, account_creation_query, account_creation_params) do
                  {:ok, %Postgrex.Result{rows: [[account_id]]}} ->
                    Logger.info(
                      "Account inserted successfully in #{product_name} with ID: #{db_user_id}"
                    )

                    # Link account to user
                    account_link_query = """
                    INSERT INTO account_users (account_id, user_id, created_at, updated_at)
                    VALUES ($1, $2, $3, $3)
                    """

                    case Postgrex.query(pid, account_link_query, [
                           account_id,
                           db_user_id,
                           email_verified
                         ]) do
                      {:ok, _result} ->
                        Logger.info("Account linked successfully in #{product_name}")

                      {:error, %Postgrex.Error{} = error} ->
                        Logger.error(
                          "Failed to link account in #{product_name}: #{inspect(error)}"
                        )
                    end

                  {:error, %Postgrex.Error{} = error} ->
                    Logger.error(
                      "Failed to insert account for #{product_name}: #{inspect(error)}"
                    )
                end

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
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

        user_query = """
        INSERT INTO "users" (name, email, "emailVerified")
        VALUES ($1, $2, $3)
        RETURNING id
        """

        user_params = [name, email, email_verified]

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

  def add_member_to_product(email, "penpot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).argon2id_hash

    try do
      # Check if the email exists
      check_query = """
      SELECT id, is_active FROM profile
      WHERE email = $1
      """

      case Postgrex.query(pid, check_query, [email]) do
        {:ok, %Postgrex.Result{rows: [[profile_id, is_active]]}} ->
          if is_active do
            Logger.info("User with email #{email} already exists and is active in penpot")
          else
            # User found but inactive, reactivate
            reactivate_query = """
            UPDATE profile SET is_active = true WHERE id = $1
            """

            case Postgrex.query(pid, reactivate_query, [profile_id]) do
              {:ok, _} ->
                Logger.info("User reactivated successfully in penpot")

              {:error, error} ->
                Logger.error("Failed to reactivate user in penpot: #{inspect(error)}")
            end
          end

        {:ok, %Postgrex.Result{rows: []}} ->
          # User not found, proceed with new user creation
          result =
            Postgrex.transaction(pid, fn conn ->
              name = extract_name_from_email(email)

              # Create a team
              team_insert_query = """
              INSERT INTO team (name, is_default)
              VALUES ($1, $2)
              RETURNING id
              """

              {:ok, %{rows: [[team_id]]}} =
                Postgrex.query(conn, team_insert_query, ["Default", true])

              # Create a project
              project_insert_query = """
              INSERT INTO project (team_id, is_default, name)
              VALUES ($1, $2, $3)
              RETURNING id
              """

              {:ok, %{rows: [[project_id]]}} =
                Postgrex.query(conn, project_insert_query, [team_id, true, "Drafts"])

              # Create a profile
              profile_insert_query = """
              INSERT INTO profile (fullname, email, password, is_demo, is_active, is_muted, auth_backend, is_blocked, default_project_id, default_team_id)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
              RETURNING id
              """

              {:ok, %{rows: [[profile_id]]}} =
                Postgrex.query(
                  conn,
                  profile_insert_query,
                  [
                    name,
                    email,
                    hashed_password,
                    false,
                    true,
                    false,
                    "penpot",
                    false,
                    project_id,
                    team_id
                  ]
                )

              # Create team_profile_rel
              team_profile_rel_insert_query = """
              INSERT INTO team_profile_rel (team_id, profile_id, is_owner, is_admin, can_edit)
              VALUES ($1, $2, $3, $4, $5)
              """

              Postgrex.query!(conn, team_profile_rel_insert_query, [
                team_id,
                profile_id,
                true,
                true,
                true
              ])

              # Create project_profile_rel
              project_profile_rel_insert_query = """
              INSERT INTO project_profile_rel (profile_id, project_id, is_owner, is_admin, can_edit)
              VALUES ($1, $2, $3, $4, $5)
              """

              Postgrex.query!(conn, project_profile_rel_insert_query, [
                profile_id,
                project_id,
                true,
                true,
                true
              ])

              {profile_id, team_id, project_id}
            end)

          case result do
            {:ok, {_profile_id, _team_id, _project_id}} ->
              Logger.info("#{product_name} user registration complete!")

            {:error, error} ->
              Logger.error("Failed to complete #{product_name} operations: #{inspect(error)}")
          end

        {:error, %Postgrex.Error{} = error} ->
          Logger.error("Error checking for existing user in penpot: #{inspect(error)}")
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

  def add_member_to_product(email, "kimai" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))
    # Check if the email exists with @onestack.cloud suffix
    check_query =
      "SELECT id, email FROM kimai2_users WHERE email LIKE ?"

    email_pattern =
      if String.ends_with?(email, "@onestack.cloud") do
        # For emails already ending in @onestack.cloud
        "#{email}%"
      else
        # For regular emails
        "#{email}@onestack.cloud%"
      end

    case MyXQL.query(conn, check_query, [email_pattern]) do
      {:ok, %MyXQL.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = "UPDATE kimai2_users SET enabled = ? WHERE id = ?"

        case MyXQL.query(conn, reactivate_query, [1, user_id]) do
          {:ok, _} ->
            Logger.info("User reactivated successfully in #{product_name}")

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %MyXQL.Result{rows: []}} ->
        # User not found, proceed with new user creation
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)
        hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

        insert_user_query = """
        INSERT INTO kimai2_users (username, email, password, enabled, roles, totp_enabled, system_account, registration_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        RETURNING id
        """

        username = generate_random_string(12)

        case MyXQL.query(conn, insert_user_query, [
               username,
               email,
               hashed_password,
               1,
               "a:1:{i:0;s:10:\"ROLE_ADMIN\";}",
               0,
               0,
               email_verified
             ]) do
          {:ok, %MyXQL.Result{rows: [[user_id]]}} ->
            Logger.info("User inserted successfully in #{product_name} with ID: #{user_id}")

          {:error, error} ->
            Logger.error("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, error} ->
        Logger.error("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end
  end

  def add_member_to_product(email, "plane" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).pkbdf2_hash
    # Check if the email exists with @onestack.cloud suffix
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
        reactivate_query = """
        UPDATE users SET email = $1 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_query, [email, user_id]) do
          {:ok, _} ->
            Logger.info("User reactivated successfully in #{product_name}")

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        # User not found, proceed with new user creation
        name = extract_name_from_email(email)
        email_verified = DateTime.utc_now()

        ua_agent = "Onestack Auto Registration"
        login_ip = "1.1.1.1"
        login_medium = "onestack_rego"
        timezone = "UTC"

        user_query = """
        INSERT INTO "users" (
          password,
          id,
          username,
          email,
          first_name,
          last_name,
          display_name,
          date_joined,
          created_at,
          updated_at,
          token,
          user_timezone,
          last_login_ip,
          last_logout_ip,
          last_login_medium,
          last_login_uagent,
          avatar,
          last_location,
          created_location,
          is_superuser,
          is_managed,
          is_password_expired,
          is_active,
          is_email_verified,
          is_staff,
          is_password_autoset,
          is_bot
        )
        VALUES ($1, $2, $3, $4, $5, $5, $5, $6, $6, $6, $7, $8, $9, $9, $10, $11, $12, $13, $13, $14, $14, $14, $14, $14, $14, $14, $14)
        RETURNING id
        """

        username = :crypto.strong_rand_bytes(128) |> Base.url_encode64() |> binary_part(0, 128)
        token = :crypto.strong_rand_bytes(64) |> Base.url_encode64() |> binary_part(0, 64)

        user_params = [
          hashed_password,
          Ecto.UUID.dump!(UUID.uuid4()),
          username,
          email,
          name,
          email_verified,
          token,
          timezone,
          login_ip,
          login_medium,
          ua_agent,
          "",
          "",
          false
        ]

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

  def add_member_to_product(email, "twenty" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash
    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT id, email FROM core.user
    WHERE email LIKE $1
    """

    case Postgrex.query(pid, check_query, [email]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE core.user SET disabled = false, "passwordHash" = $2 WHERE id = $1
        """

        case Postgrex.query(pid, reactivate_query, [user_id, hashed_password]) do
          {:ok, _} ->
            Logger.info("User reactivated successfully in #{product_name}")

          {:error, error} ->
            Logger.error("Failed to reactivate user in #{product_name}: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        # User not found, proceed with new user creation (need a new workspace first)

        name = extract_name_from_email(email)
        email_verified = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)
        datetime = DateTime.from_naive!(email_verified, "Etc/UTC")

        workspace_query = """
        INSERT INTO core.workspace ("displayName", "createdAt", "updatedAt","activationStatus","metadataVersion")
        VALUES ($1, $2, $2, $3, $4)
        RETURNING id
        """

        workspace_params = [email, datetime, "ACTIVE", 2]

        case Postgrex.query(pid, workspace_query, workspace_params) do
          {:ok, %Postgrex.Result{rows: [[workspace_id]]}} ->
            IO.puts(
              ~s(Workspace inserted successfully in #{product_name} with ID: #{Base.encode16(workspace_id)})
            )

            user_query = """
            INSERT INTO core.user (email, "emailVerified", "passwordHash", "createdAt", "updatedAt", "defaultWorkspaceId")
            VALUES ($1, $2, $3, $4, $4, $5)
            RETURNING id
            """

            user_params = [email, true, hashed_password, datetime, workspace_id]

            case Postgrex.query(pid, user_query, user_params) do
              {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
                IO.puts(
                  "User inserted successfully in #{product_name} with ID: #{Base.encode16(db_user_id)}"
                )

                user_worspace_query = """
                INSERT INTO core."userWorkspace" ("userId", "workspaceId", "createdAt", "updatedAt")
                VALUES ($1, $2, $3, $3)
                RETURNING id
                """

                user_workspace_params = [db_user_id, workspace_id, datetime]

                case Postgrex.query(pid, user_worspace_query, user_workspace_params) do
                  {:ok, %Postgrex.Result{rows: [[db_user_id]]}} ->
                    IO.puts(
                      "User <> workspace relationship inserted successfully in #{product_name} with ID: #{Base.encode16(db_user_id)}"
                    )

                  {:error, %Postgrex.Error{} = error} ->
                    IO.puts(
                      "Failed to insert user <> workspace relationship for #{product_name}: #{inspect(error)}"
                    )
                end

              {:error, %Postgrex.Error{} = error} ->
                IO.puts("Failed to insert user for #{product_name}: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to insert workspace_query for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
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

  def remove_member_from_product(email, "penpot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    query = """
    UPDATE profile
    SET is_active = false
    WHERE email = $1
    """

    params = [email]

    try do
      case Postgrex.query(pid, query, params) do
        {:ok, %Postgrex.Result{num_rows: 1}} ->
          Logger.info("User deactivated successfully in #{product_name} for email: #{email}")

        {:ok, %Postgrex.Result{num_rows: 0}} ->
          Logger.info("No user found with email #{email} in #{product_name}")

        {:error, %Postgrex.Error{} = error} ->
          Logger.error("Failed to deactivate user in #{product_name}: #{inspect(error)}")
      end
    after
      GenServer.stop(pid)
    end
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

  def remove_member_from_product(email, "kimai" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))

    # Update the user's email
    deactivate_query = "UPDATE kimai2_users SET enabled = 0 WHERE username = ?"

    case MyXQL.query(conn, deactivate_query, [email]) do
      {:ok, %MyXQL.Result{num_rows: 1}} ->
        Logger.info("User deactivated successfully in #{product_name}")

      {:ok, %MyXQL.Result{num_rows: 0}} ->
        Logger.info("No user found with email #{email} in #{product_name}")

      {:error, error} ->
        Logger.error("Error updating user in #{product_name}: #{inspect(error)}")
    end
  end

  def remove_member_from_product(email, "chatwoot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    # Update the user's email
    update_query = "UPDATE users SET email = $1, encrypted_password = $2 WHERE email = $3"
    update_params = [new_email, "", email]

    case Postgrex.query(pid, update_query, update_params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Logger.info("User deactivated successfully in #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        Logger.info("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Error updating user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
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
    url = "https://n8n.onestack.cloud/webhook/matrix/deactivate"

    headers = [
      {"Content-Type", "application/json"},
      {"onestack_matrix", "27530ad6f47e83ee0a215f42699dd52fbd50956939fdfd2a6c0cd0304c597a0e"}
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

  def remove_member_from_product(email, "plane" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # First, get the user ID
    # user_query = "SELECT id FROM users WHERE email = $1"
    # user_params = [email]

    # case Postgrex.query(pid, user_query, user_params) do
    #   {:ok, %Postgrex.Result{rows: [[user_id]]}} ->
    #     # Update UserPassword table to set hash to null
    #     password_query = "UPDATE \"UserPassword\" SET hash = '' WHERE \"userId\" = $1"

    #     case Postgrex.query(pid, password_query, [user_id]) do
    #       {:ok, _result} ->
    #         Logger.info("Password removed for #{product_name} user")

    #       {:error, %Postgrex.Error{} = error} ->
    #         Logger.error("Failed to remove password for #{product_name} user: #{inspect(error)}")
    #     end

    #   {:ok, %Postgrex.Result{rows: []}} ->
    #     Logger.info("User not found in #{product_name}")

    #   {:error, %Postgrex.Error{} = error} ->
    #     Logger.error("Error querying user in #{product_name}: #{inspect(error)}")
    # end

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

  def update_password_for_product(_email, "matrix") do
  end

  def update_password_for_product(email, "chatwoot") do
    {:ok, pid} = Postgrex.start_link(get_db_config("chatwoot"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    UPDATE users SET encrypted_password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for chatwoot user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for chatwoot user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(pid)
        {:error, error}
    end
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

  def update_password_for_product(email, "penpot") do
    {:ok, pid} = Postgrex.start_link(get_db_config("penpot"))
    hashed_password = Accounts.get_user_by_email(email).argon2id_hash

    update_query = """
    UPDATE profile SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for penpot user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for penpot user: #{email}. Error: #{inspect(error)}"
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

  def update_password_for_product(email, "kimai") do
    {:ok, conn} = MyXQL.start_link(get_db_config("kimai"))
    hashed_password = Accounts.get_user_by_email(email).bcrypt_hash

    update_query = """
    deactivate_query = "UPDATE kimai2_users SET enabled = 1, password = ? WHERE username = ?"
    """

    case MyXQL.query(conn, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for kimai user: #{email}")
        GenServer.stop(conn)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for kimai user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(conn)
        {:error, error}
    end
  end

  def update_password_for_product(email, "plane") do
    {:ok, pid} = Postgrex.start_link(get_db_config("plane"))
    hashed_password = Accounts.get_user_by_email(email).pkbdf2_hash

    update_query = """
    UPDATE users SET password = $1
    WHERE email = $2
    """

    case Postgrex.query(pid, update_query, [hashed_password, email]) do
      {:ok, result} ->
        Logger.info("Successfully updated password for plane user: #{email}")
        GenServer.stop(pid)
        {:ok, result}

      {:error, error} ->
        Logger.error(
          "Failed to update password for plane user: #{email}. Error: #{inspect(error)}"
        )

        GenServer.stop(pid)
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

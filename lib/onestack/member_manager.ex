defmodule Onestack.MemberManager do
  use GenServer
  require Logger
  alias Onestack.InvitationEmail
  alias Onestack.PasswordHasher
  alias Onestack.MatrixAccounts
  alias Onestack.MemberManagement
  alias Onestack.Repo

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
    results =
      Enum.map(products, fn product ->
        password = generate_password()
        {hashed_password, salt} = PasswordHasher.hash_password(password)
        result = add_member_to_product(email, password, hashed_password, salt, product)

        attrs = %{
          job_id: job_id,
          email: email,
          product: product,
          password: password,
          hashed_password: hashed_password,
          salt: salt,
          result: result
        }

        {:ok, _member_result} = MemberManagement.create_member_credentials(attrs)
        result
      end)

    if Enum.all?(results, &is_map/1) do
      InvitationEmail.send_invitation(email, job_id)
    else
      Logger.error("Failed to add member to all products for email: #{email}")
    end

    {:noreply, state}
  end

  def handle_cast({:remove_member, email, products, job_id}, state) do
    Enum.each(products, fn product ->
      result = remove_member_from_product(email, product)
      :ets.insert(@ets_table, {{job_id, product}, result})
    end)

    {:noreply, state}
  end

  def add_member_to_product(email, password, _hashed_password, _salt, "matrix") do
    # TODO: check if email is already in DB and if so just reset the password
    # Check if the email exists in MatrixAccounts
    case Onestack.MatrixAccounts.list_users() |> Enum.find(&(&1.email == email)) do
      nil ->
        # Email not found, proceed with registration
        registration_token = "64629919445a7d83311275026d29b708c1939bd72242d56d0ef3b756c128a75f"
        url = "https://matrix.onestack.cloud/_matrix/client/v3/register"

        body =
          Jason.encode!(%{
            email: email,
            password: password,
            initial_device_display_name: "Onestack Auto Registration",
            auth: %{
              type: "m.login.registration_token",
              token: registration_token
            }
          })

        case HTTPoison.post(url, body) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            IO.puts("User created successfully in Matrix")
            IO.puts("Generated Password for #{email}: #{password}")

            # Parse the response body
            case Jason.decode(response_body) do
              {:ok, decoded_response} ->
                user_id =
                  decoded_response["user_id"]

                # Insert user_id and email into matrix_users table
                MatrixAccounts.create_matrix_user(%{email: email, matrix_id: user_id})

                %{email: user_id, password: password}

              {:error, _} ->
                IO.puts("Failed to parse response body")
            end

          {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
            IO.puts("Failed to create user in Matrix. Status code: #{status_code}")
            IO.puts("Response: #{response_body}")

          {:error, %HTTPoison.Error{reason: reason}} ->
            IO.puts("Error creating user in Matrix: #{inspect(reason)}")
        end

      existing_user ->
        # Email found, update the existing user
        url = "https://n8n.onestack.cloud/webhook/matrix/reset_password"

        headers = [
          {"Content-Type", "application/json"},
          {"onestack_matrix", "27530ad6f47e83ee0a215f42699dd52fbd50956939fdfd2a6c0cd0304c597a0e"}
        ]

        body = Jason.encode!(%{matrix_id: existing_user.matrix_id})

        # Build and send the request
        request = Finch.build(:post, url, headers, body)

        case Finch.request(request, Onestack.Finch) do
          {:ok, response} ->
            IO.puts("Response status: #{response.status}")
            IO.puts("Response body: #{response.body}")

          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}")
        end

        Onestack.MatrixAccounts.update_matrix_user(existing_user, %{active: true})
        %{email: existing_user.matrix_id, password: password}
        IO.puts("Existing user reactivated in Matrix")
    end
  end

  def add_member_to_product(email, password, _hashed_password, _salt, "chatwoot") do
    api_url = "https://chatwoot.onestack.cloud/platform/api/v1/users"
    api_token = "9Z8ZwSuEYqAL5MQuFmwgcUYo"

    name = extract_name_from_email(email)

    headers = [
      {"Content-Type", "application/json"},
      {"api_access_token", api_token}
    ]

    body =
      Jason.encode!(%{
        name: name,
        email: email,
        password: password,
        custom_attributes: %{}
      })

    case HTTPoison.post(api_url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        IO.puts("User created successfully in chatwoot")
        IO.puts("Response: #{response_body}")
        IO.puts("Generated Password for #{email}: #{password}")
        %{email: email, password: password}

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        IO.puts("Failed to create user in chatwoot. Status code: #{status_code}")
        IO.puts("Response: #{response_body}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("Error creating user in chatwoot: #{inspect(reason)}")
    end
  end

  # Product-specific add member functions
  def add_member_to_product(email, password, hashed_password, _salt, "cal" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT id, email FROM users
    WHERE email LIKE $1
    """

    email_pattern = "#{email}@onestack.cloud%"

    case Postgrex.query(pid, check_query, [email_pattern]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE users SET email = $1, password = $3 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_query, [email, user_id]) do
          {:ok, _} ->
            password_query = """
            INSERT INTO "UserPassword" ("userId", hash)
            VALUES ($1, $2)
            """

            password_params = [user_id, hashed_password]

            case Postgrex.query(pid, password_query, password_params) do
              {:ok, _result} ->
                IO.puts("User inserted successfully in #{product_name} with ID: #{user_id}")
                IO.puts("Generated Password for #{email}: #{password}")
                IO.puts("User reactivated successfully in #{product_name}")

              {:error, %Postgrex.Error{} = error} ->
                IO.puts("Failed to insert password for #{product_name}: #{inspect(error)}")
            end

          {:error, error} ->
            IO.puts("Failed to reactivate user in #{product_name}: #{inspect(error)}")
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
                IO.puts("User inserted successfully in #{product_name} with ID: #{db_user_id}")
                IO.puts("Generated Password for #{email}: #{password}")

              {:error, %Postgrex.Error{} = error} ->
                IO.puts("Failed to insert password for #{product_name}: #{inspect(error)}")
            end

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  def add_member_to_product(email, password, hashed_password, _salt, "formbricks" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    try do
      # Check if the email exists with @onestack.cloud suffix
      check_query = """
      SELECT id, email FROM "User"
      WHERE email LIKE $1
      """

      email_pattern = "#{email}@onestack.cloud%"

      case Postgrex.query(pid, check_query, [email_pattern]) do
        {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
          # User found, reactivate by removing @onestack.cloud and random string
          reactivate_query = """
          UPDATE "User" SET email = $1 WHERE id = $2
          """

          case Postgrex.query(pid, reactivate_query, [email, user_id]) do
            {:ok, _} ->
              IO.puts("User reactivated successfully in formbricks")

            {:error, error} ->
              IO.puts("Failed to reactivate user in formbricks: #{inspect(error)}")
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
              IO.puts("#{product_name} user registration complete!")
              IO.puts("Generated Password for #{email}: #{password}")

            {:error, error} ->
              IO.puts("Failed to complete #{product_name} operations: #{inspect(error)}")
          end

          %{email: email, password: password}

        {:error, %Postgrex.Error{} = error} ->
          IO.puts("Error checking for existing user in formbricks: #{inspect(error)}")
      end

      %{email: email, password: password}
    after
      GenServer.stop(pid)
    end
  end

  def add_member_to_product(email, password, hashed_password, _salt, "penpot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    try do
      # Check if the email exists
      check_query = """
      SELECT id, is_active FROM profile
      WHERE email = $1
      """

      case Postgrex.query(pid, check_query, [email]) do
        {:ok, %Postgrex.Result{rows: [[profile_id, is_active]]}} ->
          if is_active do
            IO.puts("User with email #{email} already exists and is active in penpot")
          else
            # User found but inactive, reactivate
            reactivate_query = """
            UPDATE profile SET is_active = true WHERE id = $1
            """

            case Postgrex.query(pid, reactivate_query, [profile_id]) do
              {:ok, _} ->
                IO.puts("User reactivated successfully in penpot")

              {:error, error} ->
                IO.puts("Failed to reactivate user in penpot: #{inspect(error)}")
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
              IO.puts("#{product_name} user registration complete!")
              IO.puts("Generated Password for #{email}: #{password}")

            {:error, error} ->
              IO.puts("Failed to complete #{product_name} operations: #{inspect(error)}")
          end

        {:error, %Postgrex.Error{} = error} ->
          IO.puts("Error checking for existing user in penpot: #{inspect(error)}")
      end

      %{email: email, password: password}
    after
      GenServer.stop(pid)
    end
  end

  def add_member_to_product(email, password, hashed_password, salt, "nocodb" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT email FROM "nc_users_v2"
    WHERE email LIKE $1
    """

    email_pattern = "#{email}@onestack.cloud%"

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
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  def add_member_to_product(email, password, hashed_password, _salt, "n8n" = product_name) do
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

  def add_member_to_product(email, password, hashed_password, _salt, "castopod" = product_name) do
    {:ok, conn} = MyXQL.start_link(get_db_config(product_name))

    # Check if the email exists with @onestack.cloud suffix
    check_query =
      "SELECT id, username FROM cp_users WHERE username LIKE ?"

    email_pattern = "#{email}@onestack.cloud%"

    case MyXQL.query(conn, check_query, [email_pattern]) do
      {:ok, %MyXQL.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = "UPDATE cp_users SET username = ? WHERE id = ?"

        case MyXQL.query(conn, reactivate_query, [email, user_id]) do
          {:ok, _} ->
            IO.puts("User reactivated successfully in castopod")

          {:error, error} ->
            IO.puts("Failed to reactivate user in castopod: #{inspect(error)}")
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

      {:error, error} ->
        IO.puts("Error checking for existing user in castopod: #{inspect(error)}")
    end

    %{email: email, password: password}
  end

  def add_member_to_product(email, password, _hashed_password, _salt, "plane" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    password_hash =
      Pbkdf2.hash_pwd_salt(password, digest: :sha256, format: :django, rounds: 600_000)

    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT id, email FROM users
    WHERE email LIKE $1
    """

    email_pattern = "#{email}@onestack.cloud%"

    case Postgrex.query(pid, check_query, [email_pattern]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE users SET email = $1 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_query, [email, user_id]) do
          {:ok, _} ->
            IO.puts("User reactivated successfully in #{product_name}")

          {:error, error} ->
            IO.puts("Failed to reactivate user in #{product_name}: #{inspect(error)}")
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
          password_hash,
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
            IO.inspect("User inserted successfully in #{product_name} with ID: #{db_user_id}")

          {:error, %Postgrex.Error{} = error} ->
            IO.inspect("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        IO.inspect("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
  end

  def add_member_to_product(email, password, hashed_password, _salt, "documenso" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    # Check if the email exists with @onestack.cloud suffix
    check_query = """
    SELECT id, email FROM "User"
    WHERE email LIKE $1
    """

    email_pattern = "#{email}@onestack.cloud%"

    case Postgrex.query(pid, check_query, [email_pattern]) do
      {:ok, %Postgrex.Result{rows: [[user_id, _disabled_email]]}} ->
        # User found, reactivate by removing @onestack.cloud and random string
        reactivate_query = """
        UPDATE "User" SET email = $1, password = $3 WHERE id = $2
        """

        case Postgrex.query(pid, reactivate_query, [email, user_id, hashed_password]) do
          {:ok, _} ->
            IO.puts("User reactivated successfully in #{product_name}")

          {:error, error} ->
            IO.puts("Failed to reactivate user in #{product_name}: #{inspect(error)}")
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
            IO.puts("User inserted successfully in #{product_name} with ID: #{db_user_id}")

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to insert user for #{product_name}: #{inspect(error)}")
        end

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error checking for existing user in #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
    %{email: email, password: password}
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
            IO.puts("Password removed for #{product_name} user")

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to remove password for #{product_name} user: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        IO.puts("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error querying user in #{product_name}: #{inspect(error)}")
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
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
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
        IO.puts("User disabled successfully in #{product_name} for email: #{email}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to disable user in #{product_name}: #{inspect(error)}")
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
          IO.puts("User deactivated successfully in #{product_name} for email: #{email}")

        {:ok, %Postgrex.Result{num_rows: 0}} ->
          IO.puts("No user found with email #{email} in #{product_name}")

        {:error, %Postgrex.Error{} = error} ->
          IO.puts("Failed to deactivate user in #{product_name}: #{inspect(error)}")
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
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
  end

  def remove_member_from_product(email, "castopod") do
    {:ok, conn} = MyXQL.start_link(get_db_config("castopod"))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    # Update the user's email
    update_query = "UPDATE cp_users SET username = ? WHERE username = ?"

    case MyXQL.query(conn, update_query, [new_email, email]) do
      {:ok, %MyXQL.Result{num_rows: 1}} ->
        IO.puts("User deactivated successfully in castopod")

      {:ok, %MyXQL.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in castopod")

      {:error, error} ->
        IO.puts("Error updating user in castopod: #{inspect(error)}")
    end
  end

  def remove_member_from_product(email, "chatwoot" = product_name) do
    {:ok, pid} = Postgrex.start_link(get_db_config(product_name))

    random_string = generate_random_string(12)
    new_email = "#{email}@onestack.cloud#{random_string}"

    # Update the user's email
    update_query = "UPDATE users SET email = $1 WHERE email = $2"
    update_params = [new_email, email]

    case Postgrex.query(pid, update_query, update_params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        IO.puts("User deactivated successfully in #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error updating user in #{product_name}: #{inspect(error)}")
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
        IO.puts("User deactivated successfully in #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to update user in #{product_name}: #{inspect(error)}")
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
        IO.puts("Response status: #{response.status}")
        IO.puts("Response body: #{response.body}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
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
    #         IO.puts("Password removed for #{product_name} user")

    #       {:error, %Postgrex.Error{} = error} ->
    #         IO.puts("Failed to remove password for #{product_name} user: #{inspect(error)}")
    #     end

    #   {:ok, %Postgrex.Result{rows: []}} ->
    #     IO.puts("User not found in #{product_name}")

    #   {:error, %Postgrex.Error{} = error} ->
    #     IO.puts("Error querying user in #{product_name}: #{inspect(error)}")
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
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
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
            IO.puts("Password removed for #{product_name} user")

          {:error, %Postgrex.Error{} = error} ->
            IO.puts("Failed to remove password for #{product_name} user: #{inspect(error)}")
        end

      {:ok, %Postgrex.Result{rows: []}} ->
        IO.puts("User not found in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Error querying user in #{product_name}: #{inspect(error)}")
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
        IO.puts("#{num_rows} user(s) removed successfully from #{product_name}")

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        IO.puts("No user found with email #{email} in #{product_name}")

      {:error, %Postgrex.Error{} = error} ->
        IO.puts("Failed to remove user from #{product_name}: #{inspect(error)}")
    end

    GenServer.stop(pid)
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

  def get_job_results(job_id, clear \\ false) do
    results =
      MemberManagement.MemberCredentials
      |> where(job_id: ^job_id)
      |> Repo.all()
      |> Enum.map(fn cred -> {cred.product, %{email: cred.email, password: cred.password}} end)
      |> Enum.into(%{})

    if clear do
      # Schedule the deletion after 10 seconds
      :timer.apply_after(10_000, __MODULE__, :clear_job_results, [job_id])
    end

    results
  end

  # Add this new function to handle the delayed deletion
  def clear_job_results(job_id) do
    MemberManagement.MemberCredentials
    |> where(job_id: ^job_id)
    |> Repo.delete_all()
  end

  def generate_job_id, do: UUID.uuid4()
end

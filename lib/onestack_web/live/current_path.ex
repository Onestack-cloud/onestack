defmodule OnestackWeb.AssignCurrentPath do
  defmacro __using__(_) do
    quote do
      def handle_params(_params, uri, socket) do
        current_path = URI.parse(uri).path
        {:noreply, assign(socket, current_path: current_path)}
      end

      # Allow overriding handle_params if needed
      defoverridable handle_params: 3
    end
  end
end

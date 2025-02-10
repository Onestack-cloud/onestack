defmodule Onestack.CatalogMonthly.Features do
  @features %{
    "time_tracking" => %{
      icon: "clock",
      display_name: "Time Tracking"
    },
    "project_management" => %{
      icon: "layout-grid",
      display_name: "Project Management"
    },
    "team_chat" => %{
      icon: "message-circle",
      display_name: "Team Chat"
    },
    "design" => %{
      icon: "shapes",
      display_name: "Design Tool"
    },
    "task_management" => %{
      icon: "square-check",
      display_name: "Task Management"
    },
    "calendar" => %{
      icon: "calendar",
      display_name: "Calendar"
    },
    "form_builder" => %{
      icon: "text-cursor-input",
      display_name: "Form Builder"
    },
    "document_signing" => %{
      icon: "signature",
      display_name: "Document Signing"
    },
    "deployment" => %{
      icon: "rocket",
      display_name: "Deployment"
    },
    "podcast_hosting" => %{
      icon: "mic",
      display_name: "Podcast Hosting"
    }
  }

  def get_feature(product_name) do
    # Map product names to features
    case product_name do
      "Kimai" -> @features["time_tracking"]
      "Matrix" -> @features["project_management"]
      "Chatwoot" -> @features["team_chat"]
      "Penpot" -> @features["design"]
      "Plane" -> @features["task_management"]
      "Cal" -> @features["calendar"]
      "Formbricks" -> @features["form_builder"]
      "Documenso" -> @features["document_signing"]
      "Castopod" -> @features["podcast_hosting"]
      _ -> nil
    end
  end

  def get_icon(feature_name) when is_binary(feature_name) do
    get_in(@features, [feature_name, :icon])
  end

  def get_display_name(feature_name) when is_binary(feature_name) do
    get_in(@features, [feature_name, :display_name])
  end

  def all_features do
    @features
  end
end

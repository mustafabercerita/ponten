using System.Windows;
using System.Windows.Controls;

namespace PontenWPF
{
    public static class InputDialog
    {
        public static string? Show(Window owner, string title, string prompt, string defaultValue = "")
        {
            var dialog = new Window
            {
                Title = title,
                Width = 360,
                Height = 160,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = owner,
                ResizeMode = ResizeMode.NoResize,
                Background = System.Windows.Media.Brushes.White
            };

            var promptBlock = new TextBlock
            {
                Text = prompt,
                Margin = new Thickness(16, 16, 16, 8)
            };

            var inputBox = new TextBox
            {
                Text = defaultValue,
                Margin = new Thickness(16, 0, 16, 0),
                Padding = new Thickness(6, 4, 6, 4)
            };

            var buttonPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(16, 12, 16, 16)
            };

            string? result = null;

            var okButton = new Button
            {
                Content = "OK",
                Width = 80,
                Margin = new Thickness(0, 0, 8, 0),
                IsDefault = true
            };
            okButton.Click += (_, _) =>
            {
                result = inputBox.Text;
                dialog.DialogResult = true;
                dialog.Close();
            };

            var cancelButton = new Button
            {
                Content = "Cancel",
                Width = 80,
                IsCancel = true
            };
            cancelButton.Click += (_, _) =>
            {
                dialog.DialogResult = false;
                dialog.Close();
            };

            buttonPanel.Children.Add(okButton);
            buttonPanel.Children.Add(cancelButton);

            var layout = new Grid();
            layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid.SetRow(promptBlock, 0);
            Grid.SetRow(inputBox, 1);
            Grid.SetRow(buttonPanel, 2);

            layout.Children.Add(promptBlock);
            layout.Children.Add(inputBox);
            layout.Children.Add(buttonPanel);

            dialog.Content = layout;
            inputBox.Focus();
            inputBox.SelectAll();

            return dialog.ShowDialog() == true ? result : null;
        }
    }
}
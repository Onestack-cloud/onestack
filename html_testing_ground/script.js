const data = [
	{ product_category: 'Notes', closed_source_product: 'notion.so', open_source_product: 'affine.pro', closed_source_costs: 10, open_source_cost: 10, usd_to_aud: 1.52 },
	{ product_category: 'Project Management', closed_source_product: 'linear.app', open_source_product: 'plane.so', closed_source_costs: 10, open_source_cost: 10, usd_to_aud: 1.52 },
	{ product_category: 'Project Management', closed_source_product: 'jira', open_source_product: 'plane.so', closed_source_costs: 7.16, open_source_cost: 10, usd_to_aud: 1.52 },
	{ product_category: 'Internal Communication', closed_source_product: 'slack.com', open_source_product: 'zulip.com', closed_source_costs: 8.75, open_source_cost: 10, usd_to_aud: 1.52 },
	{ product_category: 'Scheduling', closed_source_product: 'calendly.com', open_source_product: 'cal.com', closed_source_costs: 12, open_source_cost: 10, usd_to_aud: 1.52 },
	{ product_category: 'Podcast hosting', closed_source_product: 'buzzsprout.com', open_source_product: 'castopod.org', closed_source_costs: 12, open_source_cost: 10, usd_to_aud: 1.52 }
];

function generateChart() {
	const selectedCategories = document.getElementById('product-category').value.split(',').map(category => category.trim());
	const numUsers = parseInt(document.getElementById('num-users').value);

	const filteredData = data.filter(item => selectedCategories.includes(item.product_category));

	const labels = filteredData.map(item => item.product_category);
	const closedSourceCosts = filteredData.map(item => item.closed_source_costs * item.usd_to_aud * numUsers);
	const openSourceCosts = filteredData.map(item => item.open_source_cost * numUsers);

	const totalClosedSourceCost = closedSourceCosts.reduce((sum, cost) => sum + cost, 0);
	const totalOpenSourceCost = openSourceCosts.reduce((sum, cost) => sum + cost, 0);

	document.getElementById('closed-source-cost').textContent = `AUD ${totalClosedSourceCost.toFixed(2)}`;
	document.getElementById('open-source-cost').textContent = `AUD ${totalOpenSourceCost.toFixed(2)}`;

	new Chart(document.getElementById('chart'), {
		type: 'line',
		data: {
			labels: labels,
			datasets: [
				{
					label: 'Closed Source',
					data: closedSourceCosts,
					borderColor: 'blue',
					fill: false
				},
				{
					label: 'Open Source',
					data: openSourceCosts,
					borderColor: 'green',
					fill: false
				}
			]
		},
		options: {
			responsive: true,
			scales: {
				y: {
					beginAtZero: true
				}
			}
		}
	});
}

import React from 'react';
import { NavLink } from 'react-router-dom';

interface NavigationItem {
  to: string;
  label: string;
  exact?: boolean;
}

interface NavigationProps {
  links?: NavigationItem[];
}

const Navigation: React.FC<NavigationProps> = ({ links }) => {
  // Define default navigation items if none are provided
  const defaultNavigationItems: NavigationItem[] = [
    { to: '/deposit', label: 'Deposit', exact: true },
    { to: '/withdrawal', label: 'Withdraw' },
    { to: '/delegate', label: 'Delegate' },
    { to: '/transactions', label: 'Transactions' }
    // Add more navigation items here as the app grows
  ];

  // Use provided links or default ones
  const navigationItems = links || defaultNavigationItems;

  return (
    <nav className="navigation-panel">
      <ul className="navigation-list">
        {navigationItems.map((item) => (
          <li key={item.to} className="navigation-item">
            <NavLink
              to={item.to}
              className={({ isActive }) =>
                isActive ? "navigation-link active" : "navigation-link"
              }
              end={item.exact}
            >
              {item.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
};

export default Navigation;